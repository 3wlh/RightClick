import XCTest
import RightClickCore
@testable import RightClickAppPreview

final class SettingsViewModelTests: XCTestCase {
    @MainActor
    func testConfigurationWriteFailureKeepsPreviousDocument() async throws {
        let (_, originalDocument, paths) = try fixture()
        var blockedPaths = paths
        blockedPaths.configURL = paths.baseURL.appendingPathComponent("blocked-config")
        try FileManager.default.createDirectory(at: blockedPaths.configURL, withIntermediateDirectories: true)
        let blockedModel = SettingsViewModel(paths: blockedPaths)
        blockedModel.config = originalDocument.config
        blockedModel.config.maxRootMenuActions = 9
        blockedModel.bookmarks = DirectoryBookmarkCatalog(bookmarks: [
            DirectoryBookmark(id: "new", displayName: "New", path: paths.baseURL.path)
        ])
        blockedModel.hasUnsavedChanges = true

        blockedModel.saveConfig()

        XCTAssertTrue(blockedModel.hasUnsavedChanges)
        XCTAssertEqual(try readDocument(paths), originalDocument)

        try FileManager.default.removeItem(at: blockedPaths.configURL)
        blockedModel.saveConfig()

        XCTAssertFalse(blockedModel.hasUnsavedChanges)
        let saved = try readDocument(blockedPaths)
        XCTAssertEqual(saved.config.maxRootMenuActions, 9)
        XCTAssertEqual(saved.bookmarks, blockedModel.bookmarks)
    }

    @MainActor
    func testReloadDiscardsUnsavedChanges() async throws {
        let (viewModel, _, paths) = try fixture()
        viewModel.config.maxRootMenuActions = 11
        viewModel.hasUnsavedChanges = true

        viewModel.loadOrBootstrap()

        XCTAssertFalse(viewModel.hasUnsavedChanges)
        XCTAssertEqual(viewModel.config.maxRootMenuActions, 5)
        XCTAssertEqual(try readDocument(paths).config.maxRootMenuActions, 5)
    }

    @MainActor
    func testResetCanRepairMalformedConfiguration() async throws {
        let (viewModel, _, paths) = try fixture()
        try Data("invalid JSON".utf8).write(to: paths.configURL)

        viewModel.resetToDefaults()

        XCTAssertFalse(viewModel.hasUnsavedChanges)
        let saved = try readDocument(paths).config
        XCTAssertFalse(saved.actions.isEmpty)
        XCTAssertTrue(saved.actions.contains { $0.kind == .copyPath })
        XCTAssertTrue(saved.actions.contains { $0.kind == .hideItems })
        XCTAssertTrue(saved.actions.contains { $0.kind == .unhideItems })
        XCTAssertTrue(saved.actions.contains { $0.kind == .deletePermanently })
    }

    @MainActor
    private func fixture() throws -> (SettingsViewModel, PersistedConfiguration, RightClickStoragePaths) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RightClickSettingsTests")
            .appendingPathComponent(UUID().uuidString)
        let paths = RightClickStoragePaths(baseURL: directory)
        let config = RightClickConfig(maxRootMenuActions: 5, actions: [])
        let document = PersistedConfiguration(config: config, bookmarks: DirectoryBookmarkCatalog())
        try PersistedConfigurationStore.save(document, paths: paths)
        let viewModel = SettingsViewModel(paths: paths)
        viewModel.config = config
        return (viewModel, document, paths)
    }

    private func readDocument(_ paths: RightClickStoragePaths) throws -> PersistedConfiguration {
        try XCTUnwrap(PersistedConfigurationStore.load(paths: paths)?.document)
    }
}
