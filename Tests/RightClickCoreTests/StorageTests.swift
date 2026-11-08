import XCTest
@testable import RightClickCore

final class StorageTests: XCTestCase {
    func testActionResultSupportsLegacyPayloadAndRemainingURLsRoundTrip() throws {
        let result = ActionResult(
            requestID: UUID(), status: .failure, message: "Partial failure",
            affectedURLs: [URL(fileURLWithPath: "/tmp/completed.txt")],
            remainingURLs: [URL(fileURLWithPath: "/tmp/pending.txt")]
        )
        let data = try JSONEncoder().encode(result)
        XCTAssertEqual(try JSONDecoder().decode(ActionResult.self, from: data), result)

        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "remainingURLs")
        let decoded = try JSONDecoder().decode(
            ActionResult.self,
            from: JSONSerialization.data(withJSONObject: legacy)
        )
        XCTAssertEqual(decoded.affectedURLs, result.affectedURLs)
        XCTAssertEqual(decoded.remainingURLs, [])
    }

    func testJSONFileStoreRoundTripsConfig() throws {
        let directory = try temporaryDirectory()
        let url = directory.appendingPathComponent("config.json")
        let store = JSONFileStore<RightClickConfig>(url: url)
        let config = RightClickConfig(maxRootMenuActions: 3)

        try store.save(config)
        let loaded = try store.loadRequired()

        XCTAssertEqual(loaded.maxRootMenuActions, 3)
        XCTAssertEqual(loaded.schemaVersion, RightClickConstants.currentSchemaVersion)
    }

    func testOperationLogCapsRecords() throws {
        let directory = try temporaryDirectory()
        let log = JSONLineOperationLog(url: directory.appendingPathComponent("operation-log.jsonl"), maxRecords: 2)

        try log.append(OperationRecord(actionID: "a", kind: .cut, status: .success))
        try log.append(OperationRecord(actionID: "b", kind: .paste, status: .success))
        try log.append(OperationRecord(actionID: "c", kind: .copy, status: .success))

        let records = try log.loadRecent()
        XCTAssertEqual(records.map(\.actionID), ["b", "c"])
    }

    func testDefaultStoragePrefersApplicationSupportOverAppGroupContainer() throws {
        let directory = try temporaryDirectory()
        let homeDirectory = directory.appendingPathComponent("home")
        let appGroupDirectory = directory
            .appendingPathComponent("home")
            .appendingPathComponent("Library")
            .appendingPathComponent("Group Containers")
            .appendingPathComponent(RightClickConstants.defaultAppGroupIdentifier)
        let fileManager = StoragePathFileManager(
            homeDirectory: homeDirectory,
            appGroupDirectory: appGroupDirectory
        )

        let paths = RightClickStoragePaths.defaultForCurrentProcess(
            fileManager: fileManager,
            realUserHomeDirectory: homeDirectory
        )

        XCTAssertEqual(
            paths.baseURL.path,
            homeDirectory
                .appendingPathComponent("Library")
                .appendingPathComponent("Application Support")
                .appendingPathComponent(RightClickConstants.mainAppBundleIdentifier)
                .path
        )
        XCTAssertFalse(paths.baseURL.path.contains("Group Containers"))
        XCTAssertFalse(fileManager.didRequestAppGroupContainer)
    }

    func testConfigDecodesV1JSONIntoShortcutDirectoriesAndDefaultFileOperations() throws {
        let json = """
        {
          "schemaVersion": 1,
          "maxRootMenuActions": 5,
          "monitoredDirectoryIDs": ["legacy-scope"],
          "commonDirectoryIDs": ["desktop", "downloads"],
          "actions": [],
          "fileTemplates": [],
          "developerEntrypoints": []
        }
        """

        let config = try JSONDecoder().decode(RightClickConfig.self, from: Data(json.utf8))

        XCTAssertEqual(config.schemaVersion, RightClickConstants.currentSchemaVersion)
        XCTAssertEqual(config.shortcutDirectoryIDs, ["desktop", "downloads"])
        XCTAssertEqual(config.developerEntrypoints.map(\.id), RightClickConfig.defaultDeveloperEntrypoints().map(\.id))
    }

    func testConfigSkipsRemovedCommandTemplateActionsWhenDecoding() throws {
        let json = """
        {
          "schemaVersion": 2,
          "maxRootMenuActions": 5,
          "shortcutDirectoryIDs": [],
          "actions": [
            {
              "id": "run-legacy",
              "title": "Legacy",
              "kind": "runCommand",
              "visibility": ["selection"],
              "placement": "submenu",
              "group": "commandTemplates",
              "isEnabled": true,
              "order": 10,
              "payload": {"commandTemplateID": "legacy-template"}
            },
            {
              "id": "copy-path",
              "title": "拷贝路径",
              "kind": "copyPath",
              "visibility": ["selection"],
              "placement": "submenu",
              "group": "fileOperations",
              "isEnabled": true,
              "order": 20,
              "payload": {}
            }
          ],
          "fileTemplates": [],
          "developerEntrypoints": []
        }
        """

        let config = try JSONDecoder().decode(RightClickConfig.self, from: Data(json.utf8))

        XCTAssertEqual(config.actions.map(\.id), ["copy-path"])
    }

    func testConfigEncodesV3ShortcutDirectoriesOnly() throws {
        let config = RightClickConfig(shortcutDirectoryIDs: ["desktop"])

        let data = try JSONEncoder().encode(config)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["schemaVersion"] as? Int, RightClickConstants.currentSchemaVersion)
        XCTAssertEqual(object["shortcutDirectoryIDs"] as? [String], ["desktop"])
        XCTAssertNil(object["monitoredDirectoryIDs"])
        XCTAssertNil(object["commonDirectoryIDs"])
        XCTAssertNil(object["commandTemplates"])
    }

    func testResolvedSubmenuGroupOrderKeepsValidOrderAndAppendsMissingGroups() {
        var config = RightClickConfig()
        config.submenuGroupOrder = [
            MenuGroup.fileOperations.rawValue,
            "unknown-group",
            MenuGroup.createFile.rawValue,
            MenuGroup.fileOperations.rawValue
        ]

        let resolved = config.resolvedSubmenuGroupOrder

        XCTAssertEqual(Array(resolved.prefix(2)), [.fileOperations, .createFile])
        XCTAssertEqual(resolved.count, MenuGroup.allCases.count)
        XCTAssertEqual(Set(resolved), Set(MenuGroup.allCases))
    }
}

private final class StoragePathFileManager: FileManager {
    private let providedHomeDirectory: URL
    private let appGroupDirectory: URL
    private(set) var didRequestAppGroupContainer = false

    init(homeDirectory: URL, appGroupDirectory: URL) {
        self.providedHomeDirectory = homeDirectory
        self.appGroupDirectory = appGroupDirectory
        super.init()
    }

    override var homeDirectoryForCurrentUser: URL {
        providedHomeDirectory
    }

    override func containerURL(forSecurityApplicationGroupIdentifier groupIdentifier: String) -> URL? {
        didRequestAppGroupContainer = true
        return appGroupDirectory
    }
}
