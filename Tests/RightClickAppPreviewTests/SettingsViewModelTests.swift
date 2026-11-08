import XCTest
import RightClickCore
@testable import RightClickAppPreview

final class SettingsViewModelTests: XCTestCase {
    @MainActor
    func testConfigurationWriteFailureRestoresPreviousBookmarks() async throws {
        let (originalModel, paths) = try fixture()
        var blockedPaths = paths
        blockedPaths.configURL = paths.baseURL.appendingPathComponent("blocked-config")
        try FileManager.default.createDirectory(at: blockedPaths.configURL, withIntermediateDirectories: true)
        let previousBookmarks = try Data(contentsOf: paths.bookmarksURL)
        let viewModel = SettingsViewModel(paths: blockedPaths)
        viewModel.config = originalModel.config
        viewModel.config.maxRootMenuActions = 9
        viewModel.bookmarks = DirectoryBookmarkCatalog(bookmarks: [
            DirectoryBookmark(id: "new", displayName: "New", path: paths.baseURL.path)
        ])
        viewModel.hasUnsavedChanges = true

        viewModel.saveConfig()

        XCTAssertTrue(viewModel.hasUnsavedChanges)
        XCTAssertEqual(try Data(contentsOf: paths.bookmarksURL), previousBookmarks)

        try FileManager.default.removeItem(at: blockedPaths.configURL)
        try JSONFileStore<RightClickConfig>(url: blockedPaths.configURL).save(originalModel.config)
        viewModel.saveConfig()

        XCTAssertFalse(viewModel.hasUnsavedChanges)
        XCTAssertEqual(
            try JSONFileStore<DirectoryBookmarkCatalog>(url: paths.bookmarksURL).loadRequired(),
            viewModel.bookmarks
        )
        XCTAssertEqual(
            try JSONFileStore<RightClickConfig>(url: blockedPaths.configURL).loadRequired().maxRootMenuActions,
            9
        )
    }

    @MainActor
    func testReloadDiscardsUnsavedChanges() async throws {
        let (viewModel, paths) = try fixture()
        viewModel.config.maxRootMenuActions = 11
        viewModel.hasUnsavedChanges = true

        viewModel.loadOrBootstrap()

        XCTAssertFalse(viewModel.hasUnsavedChanges)
        XCTAssertEqual(viewModel.config.maxRootMenuActions, 5)
        XCTAssertEqual(
            try JSONFileStore<RightClickConfig>(url: paths.configURL).loadRequired().maxRootMenuActions,
            5
        )
    }

    @MainActor
    func testResetCanRepairMalformedConfiguration() async throws {
        let (viewModel, paths) = try fixture()
        try Data("invalid JSON".utf8).write(to: paths.configURL)

        viewModel.resetToDefaults()

        XCTAssertFalse(viewModel.hasUnsavedChanges)
        let saved = try JSONFileStore<RightClickConfig>(url: paths.configURL).loadRequired()
        XCTAssertFalse(saved.actions.isEmpty)
        XCTAssertTrue(saved.actions.contains { $0.kind == .copyPath })
        XCTAssertTrue(saved.actions.contains { $0.kind == .hideItems })
        XCTAssertTrue(saved.actions.contains { $0.kind == .unhideItems })
        XCTAssertTrue(saved.actions.contains { $0.kind == .deletePermanently })
    }

    @MainActor
    private func fixture() throws -> (SettingsViewModel, RightClickStoragePaths) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RightClickSettingsTests")
            .appendingPathComponent(UUID().uuidString)
        let paths = RightClickStoragePaths(baseURL: directory)
        let config = RightClickConfig(maxRootMenuActions: 5, actions: [])
        try JSONFileStore<RightClickConfig>(url: paths.configURL).save(config)
        try JSONFileStore<DirectoryBookmarkCatalog>(url: paths.bookmarksURL).save(DirectoryBookmarkCatalog())
        let viewModel = SettingsViewModel(paths: paths)
        viewModel.config = config
        return (viewModel, paths)
    }
}
