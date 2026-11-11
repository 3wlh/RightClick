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
    private let fileManager: FileManager
    private let processHomeDirectoryOverride: URL?
    private let realUserHomeDirectoryOverride: URL?
    private let defaults: DefaultConfiguration

    public init(fileManager: FileManager = .default) {
        self.init(
            fileManager: fileManager,
            processHomeDirectory: nil,
            realUserHomeDirectory: nil,
            defaults: .bundled
        )
    }

    init(
        fileManager: FileManager = .default,
        processHomeDirectory: URL?,
        realUserHomeDirectory: URL?,
        defaults: DefaultConfiguration = .bundled
    ) {
        self.fileManager = fileManager
        self.processHomeDirectoryOverride = processHomeDirectory
        self.realUserHomeDirectoryOverride = realUserHomeDirectory
        self.defaults = defaults
    }

    public func bootstrap(paths: RightClickStoragePaths = .defaultForCurrentProcess()) throws -> ConfigurationBootstrapResult {
        let defaultBookmarks = defaultBookmarks()
        let didCreateConfig = !fileManager.fileExists(atPath: paths.configURL.path)
            && !fileManager.fileExists(atPath: paths.legacyConfigURL.path)
        let loaded = try PersistedConfigurationStore.load(paths: paths, fileManager: fileManager)

        // 配置文件存在时完全以文件为准；只有从未生成过配置时才写入默认目录与默认动作。
        let bookmarks = sanitizeBookmarks(loaded?.document.bookmarks ?? defaultBookmarks)
        let originalConfig = loaded?.document.config ?? defaultConfig(bookmarks: bookmarks)
        let config = repairDefaultConfig(originalConfig)
        let document = PersistedConfiguration(config: config, bookmarks: bookmarks)
        let needsSave = loaded == nil
            || loaded?.isLegacy == true
            || config != loaded?.document.config
            || bookmarks != loaded?.document.bookmarks
        if needsSave {
            try PersistedConfigurationStore.save(document, paths: paths, fileManager: fileManager)
        }

        return ConfigurationBootstrapResult(
            paths: paths,
            config: config,
            bookmarks: bookmarks,
            didCreateConfig: didCreateConfig,
            didCreateBookmarks: loaded?.isLegacy == true || didCreateConfig
        )
    }

    public func defaultBookmarks() -> DirectoryBookmarkCatalog {
        let bookmarks = defaults.directories.compactMap { directory -> DirectoryBookmark? in
            let path = expandedDirectoryPath(directory.path)
            guard fileManager.fileExists(atPath: path) else {
                return nil
            }
            return DirectoryBookmark(id: directory.id, displayName: directory.title, path: path)
        }

        return DirectoryBookmarkCatalog(bookmarks: bookmarks)
    }

    /// 展开默认目录里的 `~`。沙盒进程的 home 会指向容器，这里统一映射到真实用户目录。
    private func expandedDirectoryPath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "~" {
            return realUserHomeDirectory.path
        }
        if trimmed.hasPrefix("~/") {
            return realUserHomeDirectory
                .appendingPathComponent(String(trimmed.dropFirst(2)))
                .path
        }
        return (trimmed as NSString).expandingTildeInPath
    }

    private func repairDefaultConfig(_ config: RightClickConfig) -> RightClickConfig {
        var repaired = config

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
        let currentDefaultTemplateIDs = Set(defaults.resolvedFileTemplates.map(\.id))
        let removedIDs = templates
            .filter { template in
                // JSON 默认配置里重新声明的模板不应被当成历史遗留项删除。
                !currentDefaultTemplateIDs.contains(template.id)
                    && legacy.contains { legacyTemplate in
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

    private func defaultDirectoryActions(
        for bookmark: DirectoryBookmark,
        startingAt order: Int,
        isEnabled: Bool
    ) -> [RightClickAction] {
        [
            RightClickAction(
                id: "open-directory-\(bookmark.id)",
                title: "前往\(bookmark.displayName)",
                kind: .openDirectory,
                visibility: [.container, .toolbar],
                placement: .submenu,
                group: .commonDirectories,
                isEnabled: isEnabled,
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
                isEnabled: isEnabled,
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
                isEnabled: isEnabled,
                order: order + 20,
                payload: ActionPayload(directoryID: bookmark.id)
            )
        ]
    }

    /// 目录动作默认是否启用，由默认配置里的 `directories[].isEnabled` 控制。
    private func directoryIsEnabled(_ directoryID: String) -> Bool {
        defaults.directories.first { $0.id == directoryID }?.isEnabled ?? false
    }

    private func removeLegacyDeveloperEntrypoints(
        from entrypoints: inout [DeveloperEntrypoint],
        actions: inout [RightClickAction]
    ) {
        let legacy: [(id: String, title: String, bundleIdentifier: String)] = [
            ("developer-vscode", "在 VS Code 打开", "com.microsoft.VSCode"),
            ("developer-cursor", "在 Cursor 打开", "com.todesktop.230313mzl4w4u92")
        ]
        let currentDefaultIDs = Set(defaults.resolvedDeveloperEntrypoints.map(\.id))
        let removedIDs = entrypoints
            .filter { entrypoint in
                // JSON 默认配置里重新声明的入口不应被当成历史遗留项删除。
                !currentDefaultIDs.contains(entrypoint.id)
                    && legacy.contains { legacyEntry in
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
            uniqueKeysWithValues: defaults.resolvedDeveloperEntrypoints.map { ($0.id, $0) }
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
            maxRootMenuActions: defaults.maxRootMenuActions,
            shortcutDirectoryIDs: directoryIDs,
            actions: defaultActions(bookmarks: bookmarks),
            fileTemplates: defaults.resolvedFileTemplates,
            commandTemplates: defaults.resolvedCommandTemplates,
            developerEntrypoints: defaults.resolvedDeveloperEntrypoints,
            submenuGroupOrder: defaults.submenuGroupOrder
        )
    }

    private func defaultActions(bookmarks: DirectoryBookmarkCatalog) -> [RightClickAction] {
        var actions: [RightClickAction] = []
        var order = 10

        for action in defaults.fileOperationActions {
            actions.append(action.makeAction(order: order, defaultGroup: .fileOperations))
            order += 10
        }

        for bookmark in bookmarks.bookmarks {
            actions.append(
                contentsOf: defaultDirectoryActions(
                    for: bookmark,
                    startingAt: order,
                    isEnabled: directoryIsEnabled(bookmark.id)
                )
            )
            order += 30
        }

        for template in defaults.fileTemplates {
            let fileTemplate = template.fileTemplate
            actions.append(
                RightClickAction(
                    id: "create-\(fileTemplate.id)",
                    title: "新建\(fileTemplate.title)",
                    kind: .createFile,
                    visibility: [.container],
                    placement: .submenu,
                    group: .createFile,
                    isEnabled: template.isEnabled ?? true,
                    order: order,
                    payload: ActionPayload(templateID: fileTemplate.id)
                )
            )
            order += 10
        }

        for entrypoint in defaults.developerEntrypoints {
            let developerEntrypoint = entrypoint.developerEntrypoint
            actions.append(
                RightClickAction(
                    id: "open-\(developerEntrypoint.id)",
                    title: developerEntrypoint.title,
                    kind: .openInApp,
                    visibility: [.selection, .container, .toolbar],
                    placement: .submenu,
                    group: .developerEntrypoints,
                    isEnabled: entrypoint.isEnabled ?? true,
                    order: order,
                    payload: ActionPayload(developerEntrypointID: developerEntrypoint.id)
                )
            )
            order += 10
        }

        for template in defaults.commandTemplates {
            actions.append(
                RightClickAction(
                    id: "run-\(template.id)",
                    title: template.title,
                    kind: .runCommand,
                    visibility: [.selection, .container],
                    placement: .submenu,
                    group: .commandTemplates,
                    isEnabled: template.isEnabled ?? false,
                    order: order,
                    payload: ActionPayload(commandTemplateID: template.id)
                )
            )
            order += 10
        }

        return actions
    }
}
