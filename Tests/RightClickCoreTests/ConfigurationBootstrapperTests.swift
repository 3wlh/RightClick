import XCTest
@testable import RightClickCore

final class ConfigurationBootstrapperTests: XCTestCase {
    func testBootstrapCreatesConfigBookmarksAndDirectoryActions() throws {
        let baseDirectory = try temporaryDirectory()
        let paths = RightClickStoragePaths(baseURL: baseDirectory.appendingPathComponent("config"))
        let bootstrapper = ConfigurationBootstrapper()

        let result = try bootstrapper.bootstrap(paths: paths)

        XCTAssertTrue(result.didCreateConfig)
        XCTAssertTrue(result.didCreateBookmarks)
        XCTAssertTrue(FileManager.default.fileExists(atPath: paths.configURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.bookmarksURL.path))
        XCTAssertEqual(try readDocument(paths).bookmarks, result.bookmarks)
        XCTAssertFalse(result.config.actions.isEmpty)
        XCTAssertTrue(result.config.actions.contains { $0.kind == .createFile })
        XCTAssertTrue(result.config.actions.contains { $0.kind == .openInApp })
        XCTAssertTrue(result.config.actions.contains { $0.kind == .copyPath })
        XCTAssertTrue(result.config.actions.contains { $0.kind == .hideItems })
        XCTAssertTrue(result.config.actions.contains { $0.kind == .unhideItems })
        XCTAssertTrue(result.config.actions.contains { $0.kind == .deletePermanently })

        if !result.bookmarks.bookmarks.isEmpty {
            XCTAssertTrue(result.config.actions.contains { $0.kind == .openDirectory })
            XCTAssertEqual(result.config.schemaVersion, RightClickConstants.currentSchemaVersion)
            XCTAssertEqual(result.config.shortcutDirectoryIDs, result.bookmarks.bookmarks.map(\.id))
        }
    }

    func testDefaultBookmarksUseRealHomeWhenProcessHomeIsSandboxContainer() throws {
        let baseDirectory = try temporaryDirectory()
        let processHome = baseDirectory
            .appendingPathComponent("Library")
            .appendingPathComponent("Containers")
            .appendingPathComponent(RightClickConstants.mainAppBundleIdentifier)
            .appendingPathComponent("Data")
        let realHome = baseDirectory.appendingPathComponent("real-home")
        try FileManager.default.createDirectory(
            at: realHome.appendingPathComponent("Desktop"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: realHome.appendingPathComponent("Downloads"),
            withIntermediateDirectories: true
        )

        let bootstrapper = ConfigurationBootstrapper(
            processHomeDirectory: processHome,
            realUserHomeDirectory: realHome
        )

        let bookmarks = bootstrapper.defaultBookmarks().bookmarks

        XCTAssertEqual(bookmarks.map(\.path).sorted(), [
            realHome.appendingPathComponent("Desktop").path,
            realHome.appendingPathComponent("Downloads").path
        ].sorted())
        XCTAssertFalse(bookmarks.contains { $0.path.hasPrefix(processHome.path) })
    }

    func testBootstrapSanitizesExistingSandboxContainerBookmarks() throws {
        let baseDirectory = try temporaryDirectory()
        let paths = RightClickStoragePaths(baseURL: baseDirectory.appendingPathComponent("config"))
        let processHome = baseDirectory
            .appendingPathComponent("Library")
            .appendingPathComponent("Containers")
            .appendingPathComponent(RightClickConstants.mainAppBundleIdentifier)
            .appendingPathComponent("Data")
        let realHome = baseDirectory.appendingPathComponent("real-home")
        let createdAt = Date(timeIntervalSince1970: 100)
        let unchangedPath = processHome
            .deletingLastPathComponent()
            .appendingPathComponent("DataBackup")
            .appendingPathComponent("Desktop")
            .path
        let existingBookmarks = DirectoryBookmarkCatalog(bookmarks: [
            DirectoryBookmark(
                id: "desktop",
                displayName: "桌面",
                path: processHome.appendingPathComponent("Desktop").path,
                bookmarkDataBase64: "bookmark-data",
                addedAt: createdAt
            ),
            DirectoryBookmark(
                id: "backup",
                displayName: "Backup",
                path: unchangedPath,
                addedAt: createdAt
            )
        ])
        let bootstrapper = ConfigurationBootstrapper(
            processHomeDirectory: processHome,
            realUserHomeDirectory: realHome
        )
        try writeDocument(
            paths,
            config: bootstrapper.defaultConfig(bookmarks: existingBookmarks),
            bookmarks: existingBookmarks
        )

        let result = try bootstrapper.bootstrap(paths: paths)
        let savedBookmarks = try readDocument(paths).bookmarks

        XCTAssertFalse(result.didCreateBookmarks)
        XCTAssertEqual(
            savedBookmarks.bookmark(id: "desktop")?.path,
            realHome.appendingPathComponent("Desktop").path
        )
        XCTAssertEqual(savedBookmarks.bookmark(id: "desktop")?.bookmarkDataBase64, "bookmark-data")
        XCTAssertEqual(savedBookmarks.bookmark(id: "desktop")?.addedAt, createdAt)
        XCTAssertEqual(savedBookmarks.bookmark(id: "backup")?.path, unchangedPath)
        XCTAssertEqual(result.config.shortcutDirectoryIDs, ["desktop", "backup"])
    }

    func testBootstrapRepairsMissingDefaultDirectoryInjection() throws {
        let baseDirectory = try temporaryDirectory()
        let paths = RightClickStoragePaths(baseURL: baseDirectory.appendingPathComponent("config"))
        let processHome = baseDirectory
            .appendingPathComponent("Library")
            .appendingPathComponent("Containers")
            .appendingPathComponent(RightClickConstants.mainAppBundleIdentifier)
            .appendingPathComponent("Data")
        let realHome = baseDirectory.appendingPathComponent("real-home")
        let desktop = realHome.appendingPathComponent("Desktop")
        let downloads = realHome.appendingPathComponent("Downloads")
        try FileManager.default.createDirectory(at: desktop, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)

        let existingBookmarks = DirectoryBookmarkCatalog(bookmarks: [
            DirectoryBookmark(id: "desktop", displayName: "桌面", path: desktop.path)
        ])
        let bootstrapper = ConfigurationBootstrapper(
            processHomeDirectory: processHome,
            realUserHomeDirectory: realHome
        )
        var existingConfig = bootstrapper.defaultConfig(bookmarks: existingBookmarks)
        existingConfig.actions.append(
            RightClickAction(
                id: "custom-action",
                title: "Custom",
                kind: .paste,
                visibility: [.container],
                placement: .submenu,
                order: 999
            )
        )
        try writeDocument(paths, config: existingConfig, bookmarks: existingBookmarks)

        let result = try bootstrapper.bootstrap(paths: paths)
        let saved = try readDocument(paths)
        let savedBookmarks = saved.bookmarks
        let savedConfig = saved.config

        XCTAssertFalse(result.didCreateBookmarks)
        XCTAssertFalse(result.didCreateConfig)
        XCTAssertEqual(savedBookmarks.bookmark(id: "downloads")?.path, downloads.path)
        XCTAssertNil(savedBookmarks.bookmark(id: "code"))
        XCTAssertEqual(savedConfig.shortcutDirectoryIDs, ["desktop", "downloads"])
        XCTAssertTrue(savedConfig.actions.contains { $0.id == "custom-action" })
        XCTAssertTrue(savedConfig.actions.contains { $0.id == "open-directory-downloads" })
        XCTAssertTrue(savedConfig.actions.contains { $0.id == "move-to-downloads" })
        XCTAssertTrue(savedConfig.actions.contains { $0.id == "copy-to-downloads" })
    }

    func testBootstrapDoesNotReinjectUserDeletedDefaultDirectoryAfterMigration() throws {
        let baseDirectory = try temporaryDirectory()
        let paths = RightClickStoragePaths(baseURL: baseDirectory.appendingPathComponent("config"))
        let realHome = baseDirectory.appendingPathComponent("real-home")
        let desktop = realHome.appendingPathComponent("Desktop")
        let downloads = realHome.appendingPathComponent("Downloads")
        try FileManager.default.createDirectory(at: desktop, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)

        let bootstrapper = ConfigurationBootstrapper(
            processHomeDirectory: nil,
            realUserHomeDirectory: realHome
        )
        _ = try bootstrapper.bootstrap(paths: paths)

        var document = try readDocument(paths)
        var bookmarks = document.bookmarks
        bookmarks.bookmarks.removeAll { $0.id == "downloads" }
        var config = document.config
        config.shortcutDirectoryIDs.removeAll { $0 == "downloads" }
        config.actions.removeAll { $0.payload.directoryID == "downloads" }
        document.config = config
        document.bookmarks = bookmarks
        try writeDocument(paths, config: config, bookmarks: bookmarks)

        let result = try bootstrapper.bootstrap(paths: paths)

        XCTAssertNil(result.bookmarks.bookmark(id: "downloads"))
        XCTAssertFalse(result.config.shortcutDirectoryIDs.contains("downloads"))
        XCTAssertFalse(result.config.actions.contains { $0.payload.directoryID == "downloads" })
    }

    func testBootstrapRestoresMissingFileOperationActions() throws {
        let baseDirectory = try temporaryDirectory()
        let paths = RightClickStoragePaths(baseURL: baseDirectory.appendingPathComponent("config"))
        var config = RightClickConfig(actions: [])
        config.fileTemplates = []
        config.developerEntrypoints = []
        try writeDocument(paths, config: config, bookmarks: DirectoryBookmarkCatalog())

        _ = try ConfigurationBootstrapper().bootstrap(paths: paths)
        let savedConfig = try readDocument(paths).config

        XCTAssertTrue(savedConfig.actions.contains { $0.id == "copy-path" && $0.kind == .copyPath })
        XCTAssertTrue(savedConfig.actions.contains { $0.id == "hide-selection" && $0.kind == .hideItems })
        XCTAssertTrue(savedConfig.actions.contains { $0.id == "unhide-selection" && $0.kind == .unhideItems })
        XCTAssertTrue(savedConfig.actions.contains { $0.id == "delete-permanently" && $0.kind == .deletePermanently })
    }

    func testBootstrapRemovesLegacyDefaultGitIgnoreAndSwiftTemplates() throws {
        let baseDirectory = try temporaryDirectory()
        let paths = RightClickStoragePaths(baseURL: baseDirectory.appendingPathComponent("config"))
        var config = RightClickConfig(actions: [])
        config.fileTemplates = [
            FileTemplate(id: "template-gitignore", title: "Git Ignore", defaultFileName: ".gitignore"),
            FileTemplate(id: "template-swift", title: "Swift 文件", defaultFileName: "Untitled.swift"),
            FileTemplate(id: "template-custom", title: "自定义", defaultFileName: "Custom.kt")
        ]
        config.actions = [
            RightClickAction(
                id: "create-template-gitignore",
                title: "新建 Git Ignore",
                kind: .createFile,
                visibility: [.container],
                placement: .submenu,
                group: .createFile,
                order: 1,
                payload: ActionPayload(templateID: "template-gitignore")
            ),
            RightClickAction(
                id: "create-template-swift",
                title: "新建 Swift 文件",
                kind: .createFile,
                visibility: [.container],
                placement: .submenu,
                group: .createFile,
                order: 2,
                payload: ActionPayload(templateID: "template-swift")
            ),
            RightClickAction(
                id: "create-template-custom",
                title: "新建自定义",
                kind: .createFile,
                visibility: [.container],
                placement: .submenu,
                group: .createFile,
                order: 3,
                payload: ActionPayload(templateID: "template-custom")
            )
        ]
        config.developerEntrypoints = []
        try writeDocument(paths, config: config, bookmarks: DirectoryBookmarkCatalog())

        _ = try ConfigurationBootstrapper().bootstrap(paths: paths)
        let savedConfig = try readDocument(paths).config

        XCTAssertEqual(savedConfig.fileTemplates.map(\.id), ["template-custom"])
        XCTAssertFalse(savedConfig.actions.contains { $0.payload.templateID == "template-gitignore" })
        XCTAssertFalse(savedConfig.actions.contains { $0.payload.templateID == "template-swift" })
        XCTAssertTrue(savedConfig.actions.contains { $0.payload.templateID == "template-custom" })
    }

    func testBootstrapRenamesDefaultTextTemplateToUnnamed() throws {
        let baseDirectory = try temporaryDirectory()
        let paths = RightClickStoragePaths(baseURL: baseDirectory.appendingPathComponent("config"))
        var config = RightClickConfig(actions: [])
        config.fileTemplates = [
            FileTemplate(id: "template-txt", title: "空白文本", defaultFileName: "Untitled.txt"),
            FileTemplate(id: "template-md", title: "Markdown", defaultFileName: "Untitled.md", contents: "# Untitled\n"),
            FileTemplate(id: "template-json", title: "JSON", defaultFileName: "Untitled.json", contents: "{\n  \n}\n")
        ]
        config.developerEntrypoints = []
        try writeDocument(paths, config: config, bookmarks: DirectoryBookmarkCatalog())

        _ = try ConfigurationBootstrapper().bootstrap(paths: paths)
        let savedConfig = try readDocument(paths).config

        XCTAssertEqual(savedConfig.fileTemplates.first { $0.id == "template-txt" }?.defaultFileName, "未命名.txt")
        XCTAssertEqual(savedConfig.fileTemplates.first { $0.id == "template-md" }?.defaultFileName, "未命名.md")
        XCTAssertEqual(savedConfig.fileTemplates.first { $0.id == "template-json" }?.defaultFileName, "未命名.json")
    }

    func testDefaultDeveloperEntrypointsOnlyContainTerminal() {
        let entrypoints = RightClickConfig.defaultDeveloperEntrypoints()

        XCTAssertEqual(entrypoints.map(\.id), ["developer-terminal"])
        XCTAssertEqual(entrypoints.first?.bundleIdentifier, "com.apple.Terminal")
    }

    func testBootstrapMigratesLegacyDeveloperCustomGroupToBuiltInGroup() throws {
        let baseDirectory = try temporaryDirectory()
        let paths = RightClickStoragePaths(baseURL: baseDirectory.appendingPathComponent("config"))
        var config = RightClickConfig(actions: [
            RightClickAction(
                id: "custom-developer-action",
                title: "自定义开发者工具",
                kind: .openInApp,
                visibility: [.selection],
                placement: .submenu,
                group: nil,
                order: 1,
                payload: ActionPayload(customGroupID: "custom-developer-shortcut")
            )
        ])
        config.customGroups = [
            CustomMenuGroup(
                id: "custom-developer-shortcut",
                title: "开发者工具",
                iconSymbol: "chevron.left.forwardslash.chevron.right"
            )
        ]
        config.submenuGroupOrder = ["custom-developer-shortcut", MenuGroup.fileOperations.rawValue]
        try writeDocument(paths, config: config, bookmarks: DirectoryBookmarkCatalog())

        _ = try ConfigurationBootstrapper().bootstrap(paths: paths)
        let savedConfig = try readDocument(paths).config

        XCTAssertTrue(savedConfig.customGroups.isEmpty)
        XCTAssertEqual(savedConfig.submenuGroupOrder.first, MenuGroup.developerTools.rawValue)
        XCTAssertEqual(savedConfig.actions.first?.group, .developerTools)
        XCTAssertNil(savedConfig.actions.first?.payload.customGroupID)
        XCTAssertTrue(MenuGroup.allCases.contains(.developerTools))
    }

    func testBootstrapKeepsCommandTemplateActionsAndMigratesEditorEntrypoints() throws {
        let baseDirectory = try temporaryDirectory()
        let paths = RightClickStoragePaths(baseURL: baseDirectory.appendingPathComponent("config"))
        let legacyJSON = """
        {
          "schemaVersion": 2,
          "maxRootMenuActions": 5,
          "shortcutDirectoryIDs": [],
          "actions": [
            {
              "id": "run-command-custom",
              "title": "Custom Command",
              "kind": "runCommand",
              "visibility": ["selection", "container"],
              "placement": "submenu",
              "group": "commandTemplates",
              "isEnabled": true,
              "order": 10,
              "payload": {"commandTemplateID": "command-custom"}
            },
            {
              "id": "open-developer-vscode",
              "title": "在 VS Code 打开",
              "kind": "openInApp",
              "visibility": ["selection"],
              "placement": "submenu",
              "group": "developerEntrypoints",
              "isEnabled": true,
              "order": 20,
              "payload": {"developerEntrypointID": "developer-vscode"}
            },
            {
              "id": "copy-path",
              "title": "拷贝路径",
              "kind": "copyPath",
              "visibility": ["selection", "container"],
              "placement": "submenu",
              "group": "fileOperations",
              "isEnabled": true,
              "order": 30,
              "payload": {}
            }
          ],
          "fileTemplates": [],
          "developerEntrypoints": [
            {
              "id": "developer-vscode",
              "title": "在 VS Code 打开",
              "bundleIdentifier": "com.microsoft.VSCode",
              "targetMode": "dynamic"
            },
            {
              "id": "developer-terminal",
              "title": "在 Terminal 打开",
              "bundleIdentifier": "com.apple.Terminal",
              "targetMode": "dynamic"
            }
          ],
          "commandTemplates": [
            {"id": "command-custom", "title": "Custom Command", "command": "pwd", "workingDirectory": "currentDirectory", "timeoutSeconds": 60, "environment": "", "runInTerminal": true}
          ]
        }
        """
        try FileManager.default.createDirectory(at: paths.baseURL, withIntermediateDirectories: true)
        try Data(legacyJSON.utf8).write(to: paths.configURL, options: [.atomic])

        let result = try ConfigurationBootstrapper().bootstrap(paths: paths)

        XCTAssertTrue(result.config.actions.contains { $0.id == "run-command-custom" })
        XCTAssertTrue(result.config.commandTemplates.contains { $0.id == "command-custom" })
        XCTAssertTrue(result.config.actions.contains { $0.id == "copy-path" })
        XCTAssertFalse(result.config.developerEntrypoints.contains { $0.id == "developer-vscode" })
        XCTAssertFalse(result.config.actions.contains { $0.payload.developerEntrypointID == "developer-vscode" })
        XCTAssertTrue(result.config.developerEntrypoints.contains { $0.id == "developer-terminal" })
        XCTAssertEqual(result.config.schemaVersion, RightClickConstants.currentSchemaVersion)
    }

    func testBootstrapRepairsBuiltInDeveloperEntrypointsToDynamicTarget() throws {
        let baseDirectory = try temporaryDirectory()
        let paths = RightClickStoragePaths(baseURL: baseDirectory.appendingPathComponent("config"))
        var config = RightClickConfig()
        config.developerEntrypoints = RightClickConfig.defaultDeveloperEntrypoints().map { entrypoint in
            DeveloperEntrypoint(
                id: entrypoint.id,
                title: entrypoint.title,
                bundleIdentifier: entrypoint.bundleIdentifier,
                targetMode: .currentDirectory
            )
        }
        try writeDocument(paths, config: config, bookmarks: DirectoryBookmarkCatalog())

        let result = try ConfigurationBootstrapper().bootstrap(paths: paths)

        XCTAssertTrue(result.config.developerEntrypoints.allSatisfy { $0.targetMode == .dynamic })
    }

    private func writeDocument(
        _ paths: RightClickStoragePaths,
        config: RightClickConfig,
        bookmarks: DirectoryBookmarkCatalog
    ) throws {
        try PersistedConfigurationStore.save(
            PersistedConfiguration(config: config, bookmarks: bookmarks),
            paths: paths
        )
    }

    private func readDocument(_ paths: RightClickStoragePaths) throws -> PersistedConfiguration {
        try XCTUnwrap(PersistedConfigurationStore.load(paths: paths)?.document)
    }
}
