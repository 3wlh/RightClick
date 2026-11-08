import Foundation

public struct ConfigurationBootstrapResult: Equatable, Sendable {
    public var paths: RightClickStoragePaths
    public var config: RightClickConfig
    public var bookmarks: DirectoryBookmarkCatalog
    public var didCreateConfig: Bool
    public var didCreateBookmarks: Bool

    public init(
        paths: RightClickStoragePaths,
        config: RightClickConfig,
        bookmarks: DirectoryBookmarkCatalog,
        didCreateConfig: Bool,
        didCreateBookmarks: Bool
    ) {
        self.paths = paths
        self.config = config
        self.bookmarks = bookmarks
        self.didCreateConfig = didCreateConfig
        self.didCreateBookmarks = didCreateBookmarks
    }
}

public struct ConfigurationBootstrapper {
    private static let defaultDirectoryBootstrapMarkerName = ".default-directory-bootstrap-v1"

    private let fileManager: FileManager
    private let processHomeDirectoryOverride: URL?
    private let realUserHomeDirectoryOverride: URL?

    public init(fileManager: FileManager = .default) {
        self.init(
            fileManager: fileManager,
            processHomeDirectory: nil,
            realUserHomeDirectory: nil
        )
    }

    init(
        fileManager: FileManager = .default,
        processHomeDirectory: URL?,
        realUserHomeDirectory: URL?
    ) {
        self.fileManager = fileManager
        self.processHomeDirectoryOverride = processHomeDirectory
        self.realUserHomeDirectoryOverride = realUserHomeDirectory
    }

    public func bootstrap(paths: RightClickStoragePaths = .defaultForCurrentProcess()) throws -> ConfigurationBootstrapResult {
        let configStore = JSONFileStore<RightClickConfig>(url: paths.configURL, fileManager: fileManager)
        let bookmarkStore = JSONFileStore<DirectoryBookmarkCatalog>(url: paths.bookmarksURL, fileManager: fileManager)
        let logStore = JSONLineOperationLog(url: paths.operationLogURL, fileManager: fileManager)

        let defaultBookmarks = defaultBookmarks()
        let didCreateBookmarks = !fileManager.fileExists(atPath: paths.bookmarksURL.path)
        let originalBookmarks = try bookmarkStore.load(default: defaultBookmarks)
        let sanitizedBookmarks = sanitizeBookmarks(originalBookmarks)
        // 默认目录只在首次初始化或旧版本迁移时补齐，之后尊重用户删除。
        let shouldInjectDefaultBookmarks = didCreateBookmarks || !fileManager.fileExists(
            atPath: defaultDirectoryBootstrapMarkerURL(for: paths).path
        )
        let bookmarks = shouldInjectDefaultBookmarks
            ? repairDefaultBookmarks(sanitizedBookmarks, defaults: defaultBookmarks)
            : sanitizedBookmarks
        if didCreateBookmarks || bookmarks != originalBookmarks {
            try bookmarkStore.save(bookmarks)
        }

        let didCreateConfig = !fileManager.fileExists(atPath: paths.configURL.path)
        let originalConfig = try configStore.load(default: defaultConfig(bookmarks: bookmarks))
        let config = repairDefaultConfig(
            originalConfig,
            bookmarks: bookmarks,
            defaultBookmarkIDs: defaultBookmarks.bookmarks.map(\.id)
        )
        if didCreateConfig || config != originalConfig {
            try configStore.save(config)
        }

        if shouldInjectDefaultBookmarks {
            try Data("1\n".utf8).write(
                to: defaultDirectoryBootstrapMarkerURL(for: paths),
                options: [.atomic]
            )
        }

        if !fileManager.fileExists(atPath: paths.operationLogURL.path) {
            try logStore.append(
                OperationRecord(
                    actionID: "bootstrap",
                    kind: .unsupported,
                    status: .success,
                    destinationPaths: [paths.baseURL.path],
                    message: "RightClick 默认配置已自动注入"
                )
            )
        }

        return ConfigurationBootstrapResult(
            paths: paths,
            config: config,
            bookmarks: bookmarks,
            didCreateConfig: didCreateConfig,
            didCreateBookmarks: didCreateBookmarks
        )
    }

    private func defaultDirectoryBootstrapMarkerURL(for paths: RightClickStoragePaths) -> URL {
        paths.baseURL.appendingPathComponent(Self.defaultDirectoryBootstrapMarkerName)
    }

    public func defaultBookmarks() -> DirectoryBookmarkCatalog {
        let home = realUserHomeDirectory
        let candidates: [(String, String, URL)] = [
            ("desktop", "桌面", home.appendingPathComponent("Desktop")),
            ("downloads", "下载", home.appendingPathComponent("Downloads"))
        ]

        let bookmarks = candidates
            .filter { fileManager.fileExists(atPath: $0.2.path) }
            .map { id, displayName, url in
                DirectoryBookmark(id: id, displayName: displayName, path: url.path)
            }

        return DirectoryBookmarkCatalog(bookmarks: bookmarks)
    }

    private func repairDefaultBookmarks(
        _ catalog: DirectoryBookmarkCatalog,
        defaults: DirectoryBookmarkCatalog
    ) -> DirectoryBookmarkCatalog {
        var repaired = catalog
        var existingIDs = Set(catalog.bookmarks.map(\.id))

        for bookmark in defaults.bookmarks where existingIDs.insert(bookmark.id).inserted {
            repaired.bookmarks.append(bookmark)
        }

        return repaired
    }

    private func repairDefaultConfig(
        _ config: RightClickConfig,
        bookmarks: DirectoryBookmarkCatalog,
        defaultBookmarkIDs: [String]
    ) -> RightClickConfig {
        var repaired = config
        let bookmarkIDs = Set(bookmarks.bookmarks.map(\.id))
        let directoryIDs = defaultBookmarkIDs.filter { bookmarkIDs.contains($0) }

        appendMissing(directoryIDs, to: &repaired.shortcutDirectoryIDs)
        appendMissingDirectoryActions(for: directoryIDs, bookmarks: bookmarks, to: &repaired.actions)
        appendMissingFileOperationActions(to: &repaired.actions)
        enablePasteOnSelection(in: &repaired.actions)
        movePasteIntoFileOperationSubmenu(in: &repaired.actions)
        moveCopyPathToFileOperationFront(in: &repaired.actions)
        migrateDefaultTemplateNames(in: &repaired.fileTemplates)
        removeLegacyDefaultFileTemplates(from: &repaired.fileTemplates, actions: &repaired.actions)
        removeLegacyDeveloperEntrypoints(from: &repaired.developerEntrypoints, actions: &repaired.actions)
        removeLegacyDeveloperShortcutEntrypoint(from: &repaired.developerEntrypoints, actions: &repaired.actions)
        repairDefaultDeveloperEntrypointTargets(in: &repaired.developerEntrypoints)
        migrateLegacyDeveloperCustomGroup(
            groups: &repaired.customGroups,
            order: &repaired.submenuGroupOrder,
            actions: &repaired.actions
        )

        return repaired
    }

    /// 粘贴动作原本只在目录空白处出现，现补充支持选中文件夹时直接粘贴到该文件夹。
    private func enablePasteOnSelection(in actions: inout [RightClickAction]) {
        for index in actions.indices where actions[index].kind == .paste {
            actions[index].visibility.insert(.selection)
        }
    }

    /// 粘贴动作原来默认放在一级菜单，现统一归入「文件操作」分组。
    private func movePasteIntoFileOperationSubmenu(in actions: inout [RightClickAction]) {
        for index in actions.indices where actions[index].kind == .paste {
            actions[index].placement = .submenu
            actions[index].group = .fileOperations
        }
    }

    /// 「拷贝路径」原来排在「粘贴到此处」之后，现调整为「文件操作」分组的第一项。
    /// 只有顺序仍等于旧默认顺序时才迁移，避免覆盖用户手工调整过的排序。
    private func moveCopyPathToFileOperationFront(in actions: inout [RightClickAction]) {
        let previousDefaultIDs = [
            "paste-here",
            "cut-selection",
            "copy-path",
            "hide-selection",
            "unhide-selection",
            "delete-permanently"
        ]
        let newDefaultIDs = [
            "copy-path",
            "paste-here",
            "cut-selection",
            "hide-selection",
            "unhide-selection",
            "delete-permanently"
        ]

        let fileOperationActions = actions
            .filter { $0.group == .fileOperations && $0.placement == .submenu }
            .sorted { $0.order < $1.order }
        guard fileOperationActions.map(\.id) == previousDefaultIDs else {
            return
        }

        let orders = fileOperationActions.map(\.order)
        for (index, id) in newDefaultIDs.enumerated() {
            guard let actionIndex = actions.firstIndex(where: { $0.id == id }) else {
                continue
            }
            actions[actionIndex].order = orders[index]
        }
    }

    /// 旧版的“开发者工具”自定义分组迁移为内置默认分组。
    private func migrateLegacyDeveloperCustomGroup(
        groups: inout [CustomMenuGroup],
        order: inout [String],
        actions: inout [RightClickAction]
    ) {
        let legacyID = "custom-developer-shortcut"
        let group = MenuGroup.developerTools

        groups.removeAll { $0.id == legacyID }

        for index in actions.indices
        where actions[index].payload.customGroupID == legacyID {
            actions[index].group = group
            actions[index].payload.customGroupID = nil
        }

        var migratedOrder: [String] = []
        for rawValue in order where !migratedOrder.contains(rawValue) {
            let normalized = rawValue == legacyID ? group.rawValue : rawValue
            if !migratedOrder.contains(normalized) {
                migratedOrder.append(normalized)
            }
        }
        order = migratedOrder
    }

    private func removeLegacyDeveloperShortcutEntrypoint(
        from entrypoints: inout [DeveloperEntrypoint],
        actions: inout [RightClickAction]
    ) {
        let legacy = DeveloperEntrypoint(
            id: "developer-shortcut",
            title: "开发者快捷入口",
            bundleIdentifier: "com.apple.Terminal",
            iconSymbol: "chevron.left.forwardslash.chevron.right"
        )
        guard entrypoints.contains(where: {
            $0.id == legacy.id && $0.title == legacy.title && $0.bundleIdentifier == legacy.bundleIdentifier
        }) else {
            return
        }

        entrypoints.removeAll { $0.id == legacy.id }
        actions.removeAll { $0.payload.developerEntrypointID == legacy.id }
        actions.removeAll { $0.id == "open-developer-shortcut" }
    }

    private func migrateDefaultTemplateNames(in templates: inout [FileTemplate]) {
        let migrations: [(id: String, title: String, oldFileName: String, newFileName: String)] = [
            ("template-txt", "空白文本", "Untitled.txt", "未命名.txt"),
            ("template-md", "Markdown", "Untitled.md", "未命名.md"),
            ("template-json", "JSON", "Untitled.json", "未命名.json")
        ]

        for migration in migrations {
            guard let index = templates.firstIndex(where: {
                $0.id == migration.id
                    && $0.title == migration.title
                    && $0.defaultFileName == migration.oldFileName
            }) else {
                continue
            }
            templates[index].defaultFileName = migration.newFileName
        }
    }

    private func removeLegacyDefaultFileTemplates(
        from templates: inout [FileTemplate],
        actions: inout [RightClickAction]
    ) {
        let legacy: [(id: String, title: String, defaultFileName: String)] = [
            ("template-gitignore", "Git Ignore", ".gitignore"),
            ("template-swift", "Swift 文件", "Untitled.swift")
        ]
        let removedIDs = templates
            .filter { template in
                legacy.contains { legacyTemplate in
                    template.id == legacyTemplate.id
                        && template.title == legacyTemplate.title
                        && template.defaultFileName == legacyTemplate.defaultFileName
                }
            }
            .map(\.id)
        guard !removedIDs.isEmpty else {
            return
        }

        templates.removeAll { removedIDs.contains($0.id) }
        actions.removeAll { action in
            if action.kind == .createFile, let templateID = action.payload.templateID {
                return removedIDs.contains(templateID)
            }
            return false
        }
    }

    private func appendMissing(_ ids: [String], to existingIDs: inout [String]) {
        var seenIDs = Set(existingIDs)
        for id in ids where seenIDs.insert(id).inserted {
            existingIDs.append(id)
        }
    }

    private func appendMissingDirectoryActions(
        for directoryIDs: [String],
        bookmarks: DirectoryBookmarkCatalog,
        to actions: inout [RightClickAction]
    ) {
        var existingActionIDs = Set(actions.map(\.id))
        var order = (actions.map(\.order).max() ?? 0) + 10

        for id in directoryIDs {
            guard let bookmark = bookmarks.bookmark(id: id) else {
                continue
            }

            for action in defaultDirectoryActions(for: bookmark, startingAt: order) where existingActionIDs.insert(action.id).inserted {
                actions.append(action)
                order += 10
            }
        }
    }

    private func defaultDirectoryActions(for bookmark: DirectoryBookmark, startingAt order: Int) -> [RightClickAction] {
        [
            RightClickAction(
                id: "open-directory-\(bookmark.id)",
                title: "前往\(bookmark.displayName)",
                kind: .openDirectory,
                visibility: [.container, .toolbar],
                placement: .submenu,
                group: .commonDirectories,
                isEnabled: false,
                order: order,
                payload: ActionPayload(directoryID: bookmark.id)
            ),
            RightClickAction(
                id: "move-to-\(bookmark.id)",
                title: "移动到\(bookmark.displayName)",
                kind: .moveToDirectory,
                visibility: [.selection],
                placement: .submenu,
                group: .moveToCommonDirectory,
                isEnabled: false,
                order: order + 10,
                payload: ActionPayload(directoryID: bookmark.id)
            ),
            RightClickAction(
                id: "copy-to-\(bookmark.id)",
                title: "复制到\(bookmark.displayName)",
                kind: .copyToDirectory,
                visibility: [.selection],
                placement: .submenu,
                group: .copyToCommonDirectory,
                isEnabled: false,
                order: order + 20,
                payload: ActionPayload(directoryID: bookmark.id)
            )
        ]
    }

    private func appendMissingFileOperationActions(to actions: inout [RightClickAction]) {
        var existingActionIDs = Set(actions.map(\.id))
        var order = (actions.map(\.order).max() ?? 0) + 10

        for action in RightClickConfig.defaultFileOperationActions(startingAt: order) where existingActionIDs.insert(action.id).inserted {
            actions.append(action)
            order += 10
        }
    }

    private func removeLegacyDeveloperEntrypoints(
        from entrypoints: inout [DeveloperEntrypoint],
        actions: inout [RightClickAction]
    ) {
        let legacy: [(id: String, title: String, bundleIdentifier: String)] = [
            ("developer-vscode", "在 VS Code 打开", "com.microsoft.VSCode"),
            ("developer-cursor", "在 Cursor 打开", "com.todesktop.230313mzl4w4u92")
        ]
        let removedIDs = entrypoints
            .filter { entrypoint in
                legacy.contains { legacyEntry in
                    entrypoint.id == legacyEntry.id
                        && entrypoint.title == legacyEntry.title
                        && entrypoint.bundleIdentifier == legacyEntry.bundleIdentifier
                }
            }
            .map(\.id)
        guard !removedIDs.isEmpty else {
            return
        }

        entrypoints.removeAll { removedIDs.contains($0.id) }
        actions.removeAll { action in
            if action.kind == .openInApp, let entrypointID = action.payload.developerEntrypointID {
                return removedIDs.contains(entrypointID)
            }
            return false
        }
    }

    private func repairDefaultDeveloperEntrypointTargets(in entrypoints: inout [DeveloperEntrypoint]) {
        let defaultsByID = Dictionary(
            uniqueKeysWithValues: RightClickConfig.defaultDeveloperEntrypoints().map { ($0.id, $0) }
        )

        for index in entrypoints.indices {
            guard
                let defaultEntrypoint = defaultsByID[entrypoints[index].id],
                entrypoints[index].title == defaultEntrypoint.title,
                entrypoints[index].bundleIdentifier == defaultEntrypoint.bundleIdentifier,
                entrypoints[index].targetMode == .currentDirectory
            else {
                continue
            }

            entrypoints[index].targetMode = .dynamic
        }
    }

    /// Rewrites bookmarks that still point inside the host app sandbox container
    /// (e.g. `~/Library/Containers/.../Data/Desktop`) to the real user home
    /// equivalent. Runs on every bootstrap so existing installs self-heal without
    /// requiring the user to wipe their configuration.
    private func sanitizeBookmarks(_ catalog: DirectoryBookmarkCatalog) -> DirectoryBookmarkCatalog {
        let containerRoot = processHomeDirectory.standardizedFileURL.path
        let realHome = realUserHomeDirectory.standardizedFileURL.path
        guard containerRoot != realHome else {
            return catalog
        }
        var didChange = false
        let sanitized = catalog.bookmarks.map { bookmark -> DirectoryBookmark in
            let bookmarkPath = URL(fileURLWithPath: bookmark.path).standardizedFileURL.path
            guard let relativePath = relativePath(of: bookmarkPath, under: containerRoot) else {
                return bookmark
            }
            let newPath = relativePath.isEmpty
                ? realHome
                : (realHome as NSString).appendingPathComponent(relativePath)
            didChange = true
            return DirectoryBookmark(
                id: bookmark.id,
                displayName: bookmark.displayName,
                path: newPath,
                bookmarkDataBase64: bookmark.bookmarkDataBase64,
                addedAt: bookmark.addedAt
            )
        }
        guard didChange else { return catalog }
        return DirectoryBookmarkCatalog(schemaVersion: catalog.schemaVersion, bookmarks: sanitized)
    }

    private func relativePath(of path: String, under root: String) -> String? {
        if path == root {
            return ""
        }
        let rootPrefix = root.hasSuffix("/") ? root : root + "/"
        guard path.hasPrefix(rootPrefix) else {
            return nil
        }
        return String(path.dropFirst(rootPrefix.count))
    }

    /// Resolves the real user home directory, bypassing the App Sandbox
    /// container redirection that `homeDirectoryForCurrentUser` returns when
    /// the process is sandboxed. Falls back to the FileManager value when the
    /// real path cannot be determined.
    private var realUserHomeDirectory: URL {
        UserHomeDirectoryResolver.realUserHomeDirectory(
            processHomeDirectory: processHomeDirectory,
            override: realUserHomeDirectoryOverride
        )
    }

    private var processHomeDirectory: URL {
        processHomeDirectoryOverride ?? fileManager.homeDirectoryForCurrentUser
    }

    public func defaultConfig(bookmarks: DirectoryBookmarkCatalog) -> RightClickConfig {
        let directoryIDs = bookmarks.bookmarks.map(\.id)
        return RightClickConfig(
            shortcutDirectoryIDs: directoryIDs,
            actions: defaultActions(bookmarks: bookmarks)
        )
    }

    private func defaultActions(bookmarks: DirectoryBookmarkCatalog) -> [RightClickAction] {
        var actions = RightClickConfig.defaultFileOperationActions(startingAt: 10)
        var order = (actions.map(\.order).max() ?? 0) + 10

        for bookmark in bookmarks.bookmarks {
            actions.append(contentsOf: defaultDirectoryActions(for: bookmark, startingAt: order))
            order += 30
        }

        for template in RightClickConfig.defaultFileTemplates() {
            actions.append(
                RightClickAction(
                    id: "create-\(template.id)",
                    title: "新建\(template.title)",
                    kind: .createFile,
                    visibility: [.container],
                    placement: .submenu,
                    group: .createFile,
                    order: order,
                    payload: ActionPayload(templateID: template.id)
                )
            )
            order += 10
        }

        for entrypoint in RightClickConfig.defaultDeveloperEntrypoints() {
            actions.append(
                RightClickAction(
                    id: "open-\(entrypoint.id)",
                    title: entrypoint.title,
                    kind: .openInApp,
                    visibility: [.selection, .container, .toolbar],
                    placement: .submenu,
                    group: .developerEntrypoints,
                    order: order,
                    payload: ActionPayload(developerEntrypointID: entrypoint.id)
                )
            )
            order += 10
        }

        return actions
    }
}
