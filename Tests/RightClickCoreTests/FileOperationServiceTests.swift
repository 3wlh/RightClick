import XCTest
@testable import RightClickCore

final class FileOperationServiceTests: XCTestCase {
    func testCreateFileKeepsBothWhenDestinationExists() throws {
        let directory = try temporaryDirectory()
        let existing = directory.appendingPathComponent("README.md")
        try "# Existing\n".write(to: existing, atomically: true, encoding: .utf8)
        let service = FileOperationService(conflictResolver: FixedConflictResolver(.keepBoth))
        let template = FileTemplate(id: "readme", title: "Readme", defaultFileName: "README.md", contents: "# New\n")

        let outcome = try service.createFile(template: template, in: directory)
        let secondOutcome = try service.createFile(template: template, in: directory)

        XCTAssertEqual(outcome.destinationURL.lastPathComponent, "README2.md")
        XCTAssertEqual(secondOutcome.destinationURL.lastPathComponent, "README3.md")
        XCTAssertTrue(FileManager.default.fileExists(atPath: existing.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outcome.destinationURL.path))
    }

    func testCopyKeepsBothWhenDestinationExists() throws {
        let sourceDirectory = try temporaryDirectory()
        let destinationDirectory = try temporaryDirectory()
        let source = sourceDirectory.appendingPathComponent("notes.txt")
        let existing = destinationDirectory.appendingPathComponent("notes.txt")
        try "source".write(to: source, atomically: true, encoding: .utf8)
        try "existing".write(to: existing, atomically: true, encoding: .utf8)
        let service = FileOperationService(conflictResolver: FixedConflictResolver(.keepBoth))

        let outcomes = try service.copy([source], to: destinationDirectory)

        XCTAssertEqual(outcomes.first?.destinationURL.lastPathComponent, "notes copy.txt")
    }

    func testMoveBatchReportsCompletedAndPendingItemsIndependently() throws {
        let sourceDirectory = try temporaryDirectory()
        let destinationDirectory = try temporaryDirectory()
        let completedSource = sourceDirectory.appendingPathComponent("done.txt")
        let pendingSource = sourceDirectory.appendingPathComponent("pending.txt")
        try "done".write(to: completedSource, atomically: true, encoding: .utf8)
        let service = FileOperationService(conflictResolver: FixedConflictResolver(.keepBoth))

        let firstResult = try service.moveBatch(
            [completedSource, pendingSource],
            to: destinationDirectory
        )

        XCTAssertEqual(firstResult.completed.compactMap(\.sourceURL), [completedSource])
        XCTAssertEqual(firstResult.remainingSourceURLs, [pendingSource])
        XCTAssertEqual(firstResult.failures.map(\.sourceURL), [pendingSource])
        XCTAssertFalse(FileManager.default.fileExists(atPath: completedSource.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationDirectory.appendingPathComponent("done.txt").path))
    }

    func testCopyBatchContinuesAfterMissingSource() throws {
        let sourceDirectory = try temporaryDirectory()
        let destinationDirectory = try temporaryDirectory()
        let missing = sourceDirectory.appendingPathComponent("missing.txt")
        let existing = sourceDirectory.appendingPathComponent("existing.txt")
        try Data("contents".utf8).write(to: existing)

        let result = try FileOperationService().copyBatch([missing, existing], to: destinationDirectory)

        XCTAssertEqual(result.remainingSourceURLs, [missing])
        XCTAssertEqual(result.completed.compactMap(\.sourceURL), [existing])
        XCTAssertEqual(try String(contentsOf: existing, encoding: .utf8), "contents")
        XCTAssertEqual(try String(contentsOf: destinationDirectory.appendingPathComponent("existing.txt"), encoding: .utf8), "contents")
    }

    func testBatchCancellationPreservesAllUnprocessedItems() throws {
        let sourceDirectory = try temporaryDirectory()
        let destinationDirectory = try temporaryDirectory()
        let sources = ["first.txt", "conflict.txt", "last.txt"].map { sourceDirectory.appendingPathComponent($0) }
        for source in sources {
            try Data("source".utf8).write(to: source)
        }
        try Data("existing".utf8).write(to: destinationDirectory.appendingPathComponent("conflict.txt"))
        let service = FileOperationService(conflictResolver: FixedConflictResolver(.cancel))

        let result = try service.moveBatch(sources, to: destinationDirectory)

        XCTAssertEqual(result.completed.compactMap(\.sourceURL), [sources[0]])
        XCTAssertEqual(result.remainingSourceURLs, Array(sources.dropFirst()))
        XCTAssertEqual(result.failures.map(\.isCancellation), [true])
        XCTAssertTrue(FileManager.default.fileExists(atPath: sources[2].path))
        XCTAssertEqual(try String(contentsOf: destinationDirectory.appendingPathComponent("conflict.txt"), encoding: .utf8), "existing")
    }

    func testSetHiddenBatchTogglesHiddenFlag() throws {
        let directory = try temporaryDirectory()
        let file = directory.appendingPathComponent("secret.txt")
        try Data("secret".utf8).write(to: file)
        let service = FileOperationService()

        let hideResult = try service.setHiddenBatch([file], hidden: true)
        XCTAssertEqual(hideResult.completed.map(\.operation), [.hide])
        XCTAssertEqual(try file.resourceValues(forKeys: [.isHiddenKey]).isHidden, true)

        let unhideResult = try service.setHiddenBatch([file], hidden: false)
        XCTAssertEqual(unhideResult.completed.map(\.operation), [.unhide])
        XCTAssertEqual(try file.resourceValues(forKeys: [.isHiddenKey]).isHidden, false)
    }

    func testDeleteBatchPermanentlyRemovesItemsAndReportsMissing() throws {
        let directory = try temporaryDirectory()
        let existing = directory.appendingPathComponent("remove-me.txt")
        let missing = directory.appendingPathComponent("missing.txt")
        try Data("contents".utf8).write(to: existing)
        let trashCountBefore = try? FileManager.default.contentsOfDirectory(
            at: FileManager.default.urls(for: .trashDirectory, in: .userDomainMask)[0],
            includingPropertiesForKeys: nil
        ).count

        let result = try FileOperationService().deleteBatch([existing, missing])

        XCTAssertEqual(result.completed.compactMap(\.sourceURL), [existing])
        XCTAssertEqual(result.completed.map(\.operation), [.delete])
        XCTAssertEqual(result.remainingSourceURLs, [missing])
        XCTAssertFalse(FileManager.default.fileExists(atPath: existing.path))
        let trashCountAfter = try? FileManager.default.contentsOfDirectory(
            at: FileManager.default.urls(for: .trashDirectory, in: .userDomainMask)[0],
            includingPropertiesForKeys: nil
        ).count
        XCTAssertEqual(trashCountAfter, trashCountBefore)
    }
}
