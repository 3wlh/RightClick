#if canImport(FinderSync) && canImport(AppKit)
import AppKit
import FinderSync
import RightClickCore
import UniformTypeIdentifiers

@objc(FinderSyncController)
// FinderSync 由系统和 Dispatch 回调驱动；状态访问约束在主线程与专用串行队列中。
final class FinderSyncController: FIFinderSync, @unchecked Sendable {
    private let menuBuilder = MenuBuilder()
    /// 记录是否执行过剪切，用于决定「粘贴到此处」是否出现在菜单里。
    private var hasCutItems = false
    private let cutStateLock = NSLock()
    private let paths: RightClickStoragePaths
    private let configProvider: RightClickConfigProviding
    private let xpcClient = RightClickActionRunnerXPCClient()
    private let cacheRefreshQueue = DispatchQueue(label: "com.local.rightclick.finder-extension.cache")
    private let iconResolutionQueue = DispatchQueue(label: "com.local.rightclick.finder-extension.icons", qos: .background, attributes: .concurrent)
    private let cacheRefreshInterval: TimeInterval = 8
    private let postMenuRefreshDelay: TimeInterval = 1.0
    private let backgroundRepairDelay: TimeInterval = 8
    private let deferredIconStepDelay: TimeInterval = 0.35
    private let slowMenuLogThreshold: TimeInterval = 0.2
    private let menuIconSize = NSSize(width: 16, height: 16)
    private let menuIconBackingScale: CGFloat = 2
    private var cachedConfig = RightClickConfig(actions: [])
    private var cachedBookmarks = DirectoryBookmarkCatalog()
    private var hasLoadedConfiguration = false
    private var lastCacheRefresh = Date.distantPast
    private var isRefreshingCache = false
    private var needsForcedCacheRefresh = false
    private var iconCache: [String: NSImage] = [:]
    private var placeholderIconCache: [String: NSImage] = [:]
    private var pendingIconResolutionKeys: Set<String> = []
    private var deferredIconRequests: [DeferredIconRequest] = []
    private var isResolvingDeferredIcon = false
    private var configRefreshGeneration = 0
    private var pendingMenuActions: [Int: PendingMenuAction] = [:]
    private var nextMenuActionTag = 1
    private var volumeObserverTokens: [NSObjectProtocol] = []

    override init() {
        let paths = RightClickStoragePaths.defaultForCurrentProcess()
        self.paths = paths
        self.configProvider = FileBackedRightClickConfigProvider(paths: paths)
        super.init()
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleConfigurationChangedNotification),
            name: Notification.Name(RightClickConstants.configurationChangedNotificationName),
            object: nil
        )
        observeVolumeChanges()
        applyFallbackConfiguration()
        installGlobalFinderSyncScope()
        loadConfigurationForStartupInBackground()
        repairConfigurationInBackground(paths: paths)
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(
            self,
            name: Notification.Name(RightClickConstants.configurationChangedNotificationName),
            object: nil
        )
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        volumeObserverTokens.forEach { workspaceCenter.removeObserver($0) }
    }

    @objc private func handleConfigurationChangedNotification() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.configRefreshGeneration += 1
            self.needsForcedCacheRefresh = true
            self.refreshConfigurationFromDiskIfNeeded()
        }
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        cancelConfigurationRefreshForMenuRequest()
        let menuStart = Date()
        let context = finderContext(menuKind: menuKind)

        guard hasLoadedConfiguration else {
            return nil
        }

        var config = cachedConfig
        if !currentHasCutItems() {
            config.actions.removeAll { $0.kind == .paste }
        }
        let bookmarks = cachedBookmarks

        pendingMenuActions.removeAll()
        nextMenuActionTag = 1

        let presentation = menuBuilder.buildMenu(config: config, context: context, bookmarks: bookmarks)
        let menu = NSMenu(title: "快捷操作")

        for item in presentation.rootItems {
            menu.addItem(nsMenuItem(for: item, context: context))
        }

        for ref in config.resolvedSubmenuOrder {
            let items: [MenuItemPresentation]
            let groupTitle: String
            let iconDescriptor: MenuIconDescriptor
            switch ref {
            case .builtIn(let group):
                guard let groupItems = presentation.groupedSubmenuItems[group], !groupItems.isEmpty else {
                    continue
                }
                items = groupItems
                groupTitle = title(for: group)
                iconDescriptor = icon(for: group)
            case .custom(let id):
                guard
                    let groupItems = presentation.groupedCustomSubmenuItems[id],
                    !groupItems.isEmpty,
                    let customGroup = config.customGroups.first(where: { $0.id == id })
                else {
                    continue
                }
                items = groupItems
                groupTitle = customGroup.title
                if let symbol = customGroup.iconSymbol, !symbol.isEmpty {
                    iconDescriptor = .systemSymbol(symbol)
                } else {
                    iconDescriptor = .systemSymbol("folder")
                }
            }

            let groupItem = NSMenuItem(title: groupTitle, action: nil, keyEquivalent: "")
            groupItem.image = cachedMenuImage(for: iconDescriptor)
            let submenu = NSMenu(title: groupTitle)
            items.forEach { submenu.addItem(nsMenuItem(for: $0, context: context)) }
            groupItem.submenu = submenu
            menu.addItem(groupItem)
        }

        scheduleConfigurationRefreshAfterMenu()
        logSlowMenuIfNeeded(startedAt: menuStart, itemCount: menu.items.count)

        return menu.items.isEmpty ? nil : menu
    }

    private func loadConfigurationForStartupInBackground() {
        cacheRefreshQueue.async { [weak self] in
            guard let self else { return }
            do {
                let config = try self.configProvider.loadConfig()
                let bookmarks = try self.configProvider.loadBookmarkCatalog()
                DispatchQueue.main.async {
                    self.applyCachedConfiguration(config: config, bookmarks: bookmarks)
                }
            } catch {
                NSLog("RightClick Finder extension startup config load failed, using fallback menu: \(error.localizedDescription)")
            }
        }
    }

    private func installGlobalFinderSyncScope() {
        let roots = FinderSyncScope.syncRoots()
        FIFinderSyncController.default().directoryURLs = Set(roots)
        NSLog("RightClick Finder sync roots: \(roots.map(\.path).joined(separator: ", "))")
    }

    // 卷挂载/卸载后同步刷新作用域，否则新接入的外置盘不会出现右键菜单。
    private func observeVolumeChanges() {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let volumeNotifications: [Notification.Name] = [
            NSWorkspace.didMountNotification,
            NSWorkspace.didUnmountNotification,
            NSWorkspace.didRenameVolumeNotification
        ]

        volumeObserverTokens = volumeNotifications.map { name in
            workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.installGlobalFinderSyncScope()
            }
        }
    }

    private func repairConfigurationInBackground(paths: RightClickStoragePaths) {
        cacheRefreshQueue.asyncAfter(deadline: .now() + backgroundRepairDelay) { [weak self] in
            guard let controller = self else {
                return
            }
            do {
                let result = try ConfigurationBootstrapper().bootstrap(paths: paths)
                DispatchQueue.main.async { [weak controller] in
                    controller?.applyCachedConfiguration(config: result.config, bookmarks: result.bookmarks)
                    controller?.installGlobalFinderSyncScope()
                }
            } catch {
                NSLog("RightClick Finder extension background bootstrap failed: \(error.localizedDescription)")
            }
        }
    }

    private func refreshConfigurationFromDiskIfNeeded() {
        guard !isRefreshingCache,
              needsForcedCacheRefresh || abs(lastCacheRefresh.timeIntervalSinceNow) > cacheRefreshInterval else {
            return
        }

        isRefreshingCache = true
        needsForcedCacheRefresh = false
        cacheRefreshQueue.async { [weak self] in
            guard let self else { return }
            let loadedConfig = try? self.configProvider.loadConfig()
            let loadedBookmarks = try? self.configProvider.loadBookmarkCatalog()

            DispatchQueue.main.async {
                self.isRefreshingCache = false
                // 读取期间又收到保存通知时，重新读取，不能把旧结果当作最新配置。
                if self.needsForcedCacheRefresh {
                    self.refreshConfigurationFromDiskIfNeeded()
                    return
                }
                guard let loadedConfig, let loadedBookmarks else {
                    return
                }
                if loadedConfig != self.cachedConfig || loadedBookmarks != self.cachedBookmarks {
                    self.applyCachedConfiguration(config: loadedConfig, bookmarks: loadedBookmarks)
                    self.installGlobalFinderSyncScope()
                } else {
                    self.lastCacheRefresh = Date()
                }
            }
        }
    }

    private func applyFallbackConfiguration() {
        applyCachedConfiguration(config: RightClickConfig(), bookmarks: DirectoryBookmarkCatalog())
    }

    private func applyCachedConfiguration(config: RightClickConfig, bookmarks: DirectoryBookmarkCatalog) {
        cachedConfig = config
        cachedBookmarks = bookmarks
        hasLoadedConfiguration = true
        lastCacheRefresh = Date()
        resolveStartupIconsIfNeeded(config: config, bookmarks: bookmarks)
    }

    private func scheduleConfigurationRefreshAfterMenu() {
        configRefreshGeneration += 1
        let generation = configRefreshGeneration

        DispatchQueue.main.asyncAfter(deadline: .now() + postMenuRefreshDelay) { [weak self] in
            guard let self else { return }
            guard generation == self.configRefreshGeneration else {
                return
            }
            self.refreshConfigurationFromDiskIfNeeded()
        }
    }

    private func cancelConfigurationRefreshForMenuRequest() {
        configRefreshGeneration += 1
    }

    // 启动/配置变更后立即根据当前配置并发解析真实图标并缓存到内存，
    // 让开机后的第一次右键就能拿到完整图标。纯内存缓存，进程退出即失效，
    // 因此每次启动天然读到最新图标（App 更新换图标后无需任何失效机制）。
    private func resolveStartupIconsIfNeeded(
        config: RightClickConfig,
        bookmarks: DirectoryBookmarkCatalog
    ) {
        let icons = config.actions
            .filter(\.isEnabled)
            .map { MenuIconResolver.icon(for: $0, config: config, bookmarks: bookmarks) }
            .filter(\.requiresExternalResourceLookup)

        for icon in icons {
            let key = cacheKey(for: icon)
            guard iconCache[key] == nil, pendingIconResolutionKeys.insert(key).inserted else {
                continue
            }

            iconResolutionQueue.async { [weak self] in
                guard let self else { return }
                let image = autoreleasepool {
                    self.resolvedImage(for: icon).flatMap { self.preparedMenuImage(from: $0) }
                }

                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    if self.iconCache[key] == nil, let image {
                        self.cachePreparedMenuIcon(image, forKey: key)
                    }
                    self.pendingIconResolutionKeys.remove(key)
                }
            }
        }
    }

    private func finderContext(menuKind: FIMenuKind) -> FinderContext {
        let controller = FIFinderSyncController.default()
        let selectedItems = controller.selectedItemURLs() ?? []
        let targetDirectory = controller.targetedURL() ?? selectedItems.first?.deletingLastPathComponent() ?? URL(fileURLWithPath: NSHomeDirectory())

        switch menuKind {
        case .contextualMenuForItems:
            return FinderContext(invocation: .selection, targetDirectory: targetDirectory, selectedItems: selectedItems)
        case .contextualMenuForContainer:
            return FinderContext(invocation: .container, targetDirectory: targetDirectory, selectedItems: [])
        case .toolbarItemMenu:
            return FinderContext(invocation: .toolbar, targetDirectory: targetDirectory, selectedItems: selectedItems)
        default:
            return FinderContext(invocation: .container, targetDirectory: targetDirectory, selectedItems: selectedItems)
        }
    }

    private func nsMenuItem(for item: MenuItemPresentation, context: FinderContext) -> NSMenuItem {
        let tag = nextMenuActionTag
        nextMenuActionTag += 1
        pendingMenuActions[tag] = PendingMenuAction(actionID: item.actionID, context: context)

        let menuItem = NSMenuItem(title: item.title, action: #selector(performRightClickAction(_:)), keyEquivalent: "")
        menuItem.target = self
        menuItem.image = cachedMenuImage(for: item.icon)
        // Finder Sync does not reliably preserve representedObject when
        // dispatching the copied menu item back to the extension process.
        menuItem.tag = tag
        return menuItem
    }

    @objc(performRightClickAction:)
    func performRightClickAction(_ sender: NSMenuItem) {
        guard let pending = pendingMenuActions[sender.tag] else {
            NSLog("RightClick Finder extension received menu action without pending payload for tag: \(sender.tag)")
            return
        }
        NSLog("RightClick Finder extension performing action: \(pending.actionID)")
        let request = ActionRequest(actionID: pending.actionID, context: pending.context)
        sendToActionRunner(request)
    }

    private func sendToActionRunner(_ request: ActionRequest) {
        let actionKind = cachedConfig.actions.first(where: { $0.id == request.actionID })?.kind
        guard actionKind == .deletePermanently else {
            dispatchToActionRunner(request, actionKind: actionKind)
            return
        }

        // Finder Sync 的动作回调来自 XPC workloop，不是主线程；
        // 确认弹窗必须回到主队列执行，不能在这里同步等待。
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }
            guard MainActor.assumeIsolated({ self.confirmPermanentDeletion(for: request.context) }) else {
                NSLog("RightClick Finder extension cancelled permanent deletion: \(request.actionID)")
                return
            }
            self.dispatchToActionRunner(request, actionKind: actionKind)
        }
    }

    private func dispatchToActionRunner(_ request: ActionRequest, actionKind: ActionKind?) {
        xpcClient.perform(request) { result in
            switch result {
            case .success(let actionResult):
                NSLog("RightClick ActionRunner result for \(request.actionID): \(actionResult.status.rawValue) \(actionResult.message)")
                self.updateCutState(actionKind: actionKind, result: actionResult)
                if actionResult.status != .success {
                    self.publishActionFailure(request: request, actionKind: actionKind, message: actionResult.message)
                }
            case .failure(let error):
                NSLog("RightClick ActionRunner failed for \(request.actionID): \(error.localizedDescription)")
                self.publishActionFailure(request: request, actionKind: actionKind, message: error.localizedDescription)
            }
        }
    }

    private func currentHasCutItems() -> Bool {
        cutStateLock.lock()
        defer { cutStateLock.unlock() }
        return hasCutItems
    }

    private func setHasCutItems(_ value: Bool) {
        cutStateLock.lock()
        hasCutItems = value
        cutStateLock.unlock()
    }

    /// 剪切成功后显示「粘贴到此处」；粘贴完成后再次隐藏。
    private func updateCutState(actionKind: ActionKind?, result: ActionResult) {
        guard let actionKind, result.status == .success else {
            return
        }
        switch actionKind {
        case .cut:
            setHasCutItems(true)
        case .paste:
            if result.remainingURLs.isEmpty {
                setHasCutItems(false)
            }
        default:
            break
        }
    }

    private func publishActionFailure(request: ActionRequest, actionKind: ActionKind?, message: String) {
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name(RightClickConstants.actionFailureNotificationName),
            object: nil,
            userInfo: [
                RightClickConstants.actionFailureActionIDKey: request.actionID,
                RightClickConstants.actionFailureActionKindKey: actionKind?.rawValue ?? "unknown",
                RightClickConstants.actionFailureMessageKey: message
            ],
            deliverImmediately: true
        )
    }

    @MainActor
    private func confirmPermanentDeletion(for context: FinderContext) -> Bool {
        let items = context.selectedItems
        guard !items.isEmpty else {
            return true
        }

        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "永久删除 \(items.count) 项？"
        var details = "以下内容将被永久删除，不会进入废纸篓，且无法撤销：\n"
            + items.prefix(5).map(\.lastPathComponent).joined(separator: "、")
        if items.count > 5 {
            details += " 等共 \(items.count) 项"
        }
        alert.informativeText = details
        alert.addButton(withTitle: "永久删除")
        alert.addButton(withTitle: "取消")
        alert.window.level = .modalPanel
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func icon(for group: MenuGroup) -> MenuIconDescriptor {
        switch group {
        case .commonDirectories, .moveToCommonDirectory, .copyToCommonDirectory:
            return .folder
        case .createFile:
            return .systemSymbol("doc.badge.plus")
        case .developerEntrypoints:
            return .systemSymbol("square.grid.2x2")
        case .developerTools:
            return .systemSymbol("chevron.left.forwardslash.chevron.right")
        case .fileOperations:
            return .systemSymbol("doc.on.doc")
        }
    }

    private func cachedMenuImage(for icon: MenuIconDescriptor?) -> NSImage? {
        guard let icon else {
            return nil
        }

        // 菜单回调只走缓存/占位图标；启动时已按配置并发预热真实图标，
        // 未就绪的交给后台队列解析，避免阻塞菜单弹出。
        let key = cacheKey(for: icon)
        if let cached = iconCache[key] {
            return cached
        }

        // 文件类型图标来自系统 UTType，解析开销很小，可直接取真实图标以与设置页保持一致。
        if case .fileExtension = icon,
           let image = resolvedImage(for: icon).flatMap(preparedMenuImage(from:)) {
            iconCache[key] = image
            return image
        }

        return placeholderMenuImage(for: icon)
    }

    private func placeholderMenuImage(for icon: MenuIconDescriptor) -> NSImage? {
        switch icon {
        case .appBundleIdentifier:
            return defaultAppIcon()
        case .filePath:
            return placeholderMenuImage(for: icon.lightweightFallback)
        case .systemSymbol(let name):
            return cachedPlaceholderSystemSymbol(name: name, cacheKey: "symbol:\(name)")
        case .fileExtension:
            return cachedPlaceholderSystemSymbol(name: "doc", cacheKey: "file-extension")
        case .folder:
            return cachedPlaceholderSystemSymbol(name: "folder", cacheKey: "folder")
        }
    }

    private func scheduleDeferredIconResolution(_ icon: MenuIconDescriptor, cacheKey: String) {
        guard iconCache[cacheKey] == nil else {
            return
        }
        guard pendingIconResolutionKeys.insert(cacheKey).inserted else {
            return
        }

        deferredIconRequests.append(DeferredIconRequest(key: cacheKey, icon: icon))
        processNextDeferredIconIfNeeded()
    }

    private func processNextDeferredIconIfNeeded() {
        guard !isResolvingDeferredIcon, !deferredIconRequests.isEmpty else {
            return
        }

        isResolvingDeferredIcon = true
        let request = deferredIconRequests.removeFirst()

        iconResolutionQueue.asyncAfter(deadline: .now() + deferredIconStepDelay) { [weak self] in
            guard let self else {
                return
            }

            let image: NSImage? = autoreleasepool {
                guard
                    let resolvedImage = self.resolvedImage(for: request.icon),
                    let preparedImage = self.preparedMenuImage(from: resolvedImage)
                else {
                    return nil
                }
                return preparedImage
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }

                if self.iconCache[request.key] == nil, let image {
                    self.cachePreparedMenuIcon(image, forKey: request.key)
                }
                self.pendingIconResolutionKeys.remove(request.key)
                self.isResolvingDeferredIcon = false
                self.processNextDeferredIconIfNeeded()
            }
        }
    }

    private func defaultAppIcon() -> NSImage? {
        let key = "app:__default__"
        return cachedPlaceholderSystemSymbol(name: "app", cacheKey: key)
    }

    private func cachedPlaceholderSystemSymbol(name: String, cacheKey: String) -> NSImage? {
        if let cached = placeholderIconCache[cacheKey] {
            return cached
        }
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else {
            return nil
        }
        cachePlaceholder(image, forKey: cacheKey)
        return placeholderIconCache[cacheKey]
    }

    private func resolvedAppIcon(bundleIdentifier: String) -> NSImage? {
        let normalizedBundleIdentifier = bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedBundleIdentifier.isEmpty else {
            return NSWorkspace.shared.icon(for: .applicationBundle)
        }

        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: normalizedBundleIdentifier) else {
            return NSWorkspace.shared.icon(for: .applicationBundle)
        }

        return NSWorkspace.shared.icon(forFile: appURL.path)
    }

    private func resolvedFilePathIcon(path: String) -> NSImage? {
        let normalizedPath = NSString(string: path).expandingTildeInPath
        guard !normalizedPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: normalizedPath)
    }

    private func resolvedImage(for icon: MenuIconDescriptor) -> NSImage? {
        let image: NSImage?
        switch icon {
        case .systemSymbol(let name):
            image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        case .appBundleIdentifier(let bundleIdentifier):
            image = resolvedAppIcon(bundleIdentifier: bundleIdentifier)
        case .filePath(let path):
            image = resolvedFilePathIcon(path: path)
        case .fileExtension(let fileExtension):
            image = nsImageForFileExtension(fileExtension)
        case .folder:
            image = NSWorkspace.shared.icon(for: .folder)
        }

        return image
    }

    private func preparedMenuImage(from image: NSImage) -> NSImage? {
        guard let sourceImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }

        let pixelWidth = max(1, Int(menuIconSize.width * menuIconBackingScale))
        let pixelHeight = max(1, Int(menuIconSize.height * menuIconBackingScale))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard
            let context = CGContext(
                data: nil,
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            return nil
        }

        let targetRect = CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
        context.clear(targetRect)
        context.interpolationQuality = .high
        context.draw(sourceImage, in: targetRect)

        guard let renderedImage = context.makeImage() else {
            return nil
        }

        let representation = NSBitmapImageRep(cgImage: renderedImage)
        representation.size = menuIconSize
        let menuImage = NSImage(size: menuIconSize)
        menuImage.addRepresentation(representation)
        return menuImage
    }

    private func cachePreparedMenuIcon(_ image: NSImage, forKey key: String) {
        image.size = menuIconSize
        iconCache[key] = image
    }

    private func cachePlaceholder(_ image: NSImage, forKey key: String) {
        if let copiedImage = image.copy() as? NSImage {
            copiedImage.size = menuIconSize
            placeholderIconCache[key] = copiedImage
            return
        }
        image.size = menuIconSize
        placeholderIconCache[key] = image
    }

    private func cacheKey(for icon: MenuIconDescriptor) -> String {
        switch icon {
        case .systemSymbol(let name):
            return "symbol:\(name)"
        case .appBundleIdentifier(let bundleIdentifier):
            return "app:\(bundleIdentifier)"
        case .filePath(let path):
            return "path:\(path)"
        case .fileExtension(let fileExtension):
            return "extension:\(normalizedFileExtension(fileExtension))"
        case .folder:
            return "folder"
        }
    }

    private func normalizedFileExtension(_ fileExtension: String) -> String {
        fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    private func nsImageForFileExtension(_ fileExtension: String) -> NSImage {
        let normalized = normalizedFileExtension(fileExtension)
        let contentType = UTType(filenameExtension: normalized) ?? .data
        return NSWorkspace.shared.icon(for: contentType)
    }

    private func logSlowMenuIfNeeded(startedAt: Date, itemCount: Int) {
        let duration = Date().timeIntervalSince(startedAt)
        guard duration > slowMenuLogThreshold else {
            return
        }
        NSLog("RightClick Finder menu slow render: \(String(format: "%.3f", duration))s, items=\(itemCount)")
    }

    private func title(for group: MenuGroup) -> String {
        switch group {
        case .commonDirectories:
            return "前往常用目录"
        case .moveToCommonDirectory:
            return "移动到常用目录"
        case .copyToCommonDirectory:
            return "复制到常用目录"
        case .createFile:
            return "新建文件"
        case .developerEntrypoints:
            return "应用快捷入口"
        case .developerTools:
            return "开发者工具"
        case .fileOperations:
            return "文件操作"
        }
    }
}

private final class PendingMenuAction: NSObject {
    let actionID: String
    let context: FinderContext

    init(actionID: String, context: FinderContext) {
        self.actionID = actionID
        self.context = context
    }
}

private struct DeferredIconRequest: Sendable {
    let key: String
    let icon: MenuIconDescriptor
}
#endif
