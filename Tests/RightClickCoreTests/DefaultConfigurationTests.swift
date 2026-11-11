import XCTest
@testable import RightClickCore

final class DefaultConfigurationTests: XCTestCase {
    func testEmbeddedDefaultConfigurationMatchesDefaults() throws {
        let configuration = DefaultConfiguration.bundled

        XCTAssertEqual(configuration.maxRootMenuActions, RightClickConstants.defaultMaxRootMenuActions)
        XCTAssertEqual(configuration.directories.map(\.id), ["desktop", "downloads"])
        XCTAssertEqual(configuration.directories.first { $0.id == "desktop" }?.isEnabled, false)
        XCTAssertEqual(configuration.fileOperationActions.map(\.id), [
            "copy-path",
            "paste-here",
            "cut-selection",
            "hide-selection",
            "unhide-selection",
            "delete-permanently",
            "airdrop-share"
        ])
        XCTAssertEqual(configuration.resolvedFileTemplates, RightClickConfig.defaultFileTemplates())
        XCTAssertEqual(configuration.resolvedDeveloperEntrypoints.map(\.id), ["developer-terminal"])
        XCTAssertEqual(configuration.resolvedCommandTemplates, RightClickConfig.defaultCommandTemplates())
        XCTAssertEqual(configuration.commandTemplates.first?.isEnabled, false)
        XCTAssertEqual(configuration.fileTemplates.first?.isEnabled, true)
        XCTAssertEqual(configuration.developerEntrypoints.first?.isEnabled, true)
    }

    func testFallbackMatchesHardcodedDefaults() {
        let fallback = DefaultConfiguration.fallback

        XCTAssertEqual(
            fallback.fileOperationActions.map(\.id),
            RightClickConfig.defaultFileOperationActions().map(\.id)
        )
        XCTAssertEqual(fallback.resolvedFileTemplates, RightClickConfig.defaultFileTemplates())
        XCTAssertEqual(fallback.resolvedDeveloperEntrypoints, RightClickConfig.defaultDeveloperEntrypoints())
        XCTAssertEqual(fallback.resolvedCommandTemplates, RightClickConfig.defaultCommandTemplates())
        XCTAssertEqual(fallback.directories.map(\.id), ["desktop", "downloads"])
    }

    func testBootstrapUsesInjectedDefaultsAndSkipsMissingDirectories() throws {
        let baseDirectory = try temporaryDirectory()
        let existingDirectory = baseDirectory.appendingPathComponent("custom")
        try FileManager.default.createDirectory(at: existingDirectory, withIntermediateDirectories: true)
        let missingDirectory = baseDirectory.appendingPathComponent("missing")

        let json = """
        {
          "maxRootMenuActions": 3,
          "submenuGroupOrder": ["fileOperations", "createFile"],
          "directories": [
            { "id": "custom", "title": "自定义", "path": "\(existingDirectory.path)", "isEnabled": true },
            { "id": "missing", "title": "缺失", "path": "\(missingDirectory.path)" }
          ],
          "fileOperationActions": [
            { "id": "copy-path", "title": "拷贝路径", "kind": "copyPath", "visibility": ["selection", "container"] }
          ],
          "fileTemplates": [
            { "id": "template-custom", "title": "自定义模板", "defaultFileName": "custom.txt", "contents": "hello" }
          ],
          "developerEntrypoints": [],
          "commandTemplates": []
        }
        """
        let defaults = try JSONDecoder().decode(DefaultConfiguration.self, from: Data(json.utf8))
        let paths = RightClickStoragePaths(baseURL: baseDirectory.appendingPathComponent("config"))
        let bootstrapper = ConfigurationBootstrapper(
            processHomeDirectory: nil,
            realUserHomeDirectory: baseDirectory,
            defaults: defaults
        )

        let result = try bootstrapper.bootstrap(paths: paths)

        XCTAssertEqual(result.config.maxRootMenuActions, 3)
        XCTAssertEqual(result.config.submenuGroupOrder, ["fileOperations", "createFile"])
        XCTAssertEqual(result.bookmarks.bookmarks.map(\.id), ["custom"])
        XCTAssertEqual(result.bookmarks.bookmark(id: "custom")?.displayName, "自定义")
        XCTAssertEqual(result.config.shortcutDirectoryIDs, ["custom"])
        XCTAssertEqual(result.config.fileTemplates, [
            FileTemplate(id: "template-custom", title: "自定义模板", defaultFileName: "custom.txt", contents: "hello")
        ])
        XCTAssertEqual(result.config.commandTemplates, [])
        XCTAssertEqual(result.config.developerEntrypoints, [])

        XCTAssertTrue(result.config.actions.contains { $0.id == "copy-path" })
        XCTAssertTrue(result.config.actions.contains { $0.id == "open-directory-custom" })
        XCTAssertEqual(
            result.config.actions.first { $0.id == "open-directory-custom" }?.isEnabled,
            true
        )
        XCTAssertTrue(result.config.actions.contains { $0.id == "create-template-custom" })
        XCTAssertFalse(result.config.actions.contains { $0.id == "hide-selection" })
        XCTAssertFalse(result.config.actions.contains { $0.id.contains("missing") })
    }

    func testCommandTemplateIsEnabledControlsGeneratedAction() throws {
        let baseDirectory = try temporaryDirectory()
        let json = """
        {
          "directories": [],
          "fileOperationActions": [],
          "fileTemplates": [],
          "developerEntrypoints": [],
          "commandTemplates": [
            { "id": "command-enabled", "title": "启用的命令", "command": "ls", "isEnabled": true },
            { "id": "command-disabled", "title": "禁用的命令", "command": "pwd" }
          ]
        }
        """
        let defaults = try JSONDecoder().decode(DefaultConfiguration.self, from: Data(json.utf8))
        let paths = RightClickStoragePaths(baseURL: baseDirectory.appendingPathComponent("config"))
        let result = try ConfigurationBootstrapper(
            processHomeDirectory: nil,
            realUserHomeDirectory: baseDirectory,
            defaults: defaults
        ).bootstrap(paths: paths)

        XCTAssertEqual(result.config.commandTemplates.map(\.id), ["command-enabled", "command-disabled"])
        XCTAssertEqual(result.config.actions.first { $0.id == "run-command-enabled" }?.isEnabled, true)
        XCTAssertEqual(result.config.actions.first { $0.id == "run-command-disabled" }?.isEnabled, false)
    }

    func testExistingConfigIsNotRepairedFromJSONDefaults() throws {
        let baseDirectory = try temporaryDirectory()
        let json = """
        {
          "directories": [],
          "fileOperationActions": [
            { "id": "copy-path", "title": "拷贝路径", "kind": "copyPath", "visibility": ["selection"] }
          ],
          "fileTemplates": [],
          "developerEntrypoints": [],
          "commandTemplates": []
        }
        """
        let defaults = try JSONDecoder().decode(DefaultConfiguration.self, from: Data(json.utf8))
        let paths = RightClickStoragePaths(baseURL: baseDirectory.appendingPathComponent("config"))
        let created = try ConfigurationBootstrapper(
            processHomeDirectory: nil,
            realUserHomeDirectory: baseDirectory,
            defaults: defaults
        ).bootstrap(paths: paths)
        XCTAssertFalse(created.config.actions.isEmpty)

        var config = try XCTUnwrap(PersistedConfigurationStore.load(paths: paths)?.document.config)
        config.actions = []
        try PersistedConfigurationStore.save(
            PersistedConfiguration(config: config, bookmarks: DirectoryBookmarkCatalog()),
            paths: paths
        )

        let repaired = try ConfigurationBootstrapper(
            processHomeDirectory: nil,
            realUserHomeDirectory: baseDirectory,
            defaults: defaults
        ).bootstrap(paths: paths)

        XCTAssertTrue(repaired.config.actions.isEmpty)
    }
}
