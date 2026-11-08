import XCTest
@testable import RightClickCore

final class FinderSyncScopeTests: XCTestCase {
    func testSyncRootsStartWithGlobalRoot() {
        let roots = FinderSyncScope.syncRoots()

        XCTAssertEqual(roots.first?.path, "/")
    }

    func testSyncRootsIncludeEveryBrowsableMountedVolume() {
        let roots = FinderSyncScope.syncRoots()
        let mountedVolumes = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeIsBrowsableKey],
            options: []
        ) ?? []

        for volume in mountedVolumes where volume.isFileURL {
            let isBrowsable = (try? volume.resourceValues(forKeys: [.volumeIsBrowsableKey]))?.volumeIsBrowsable ?? false
            guard isBrowsable else {
                continue
            }
            XCTAssertTrue(
                roots.contains { $0.path == volume.path },
                "已挂载卷 \(volume.path) 未加入 Finder Sync 作用域"
            )
        }
    }

    func testSyncRootsDoNotContainDuplicateVolumes() {
        let paths = FinderSyncScope.syncRoots().map(\.path)

        XCTAssertEqual(paths.count, Set(paths).count)
    }

    func testGlobalScopeAcceptsAnyFinderContext() {
        let context = FinderContext(
            invocation: .selection,
            targetDirectory: URL(fileURLWithPath: "/System"),
            selectedItems: [URL(fileURLWithPath: "/Users/test/Desktop/file.txt")]
        )

        XCTAssertTrue(FinderSyncScope.contextIsInGlobalScope(context))
    }
}
