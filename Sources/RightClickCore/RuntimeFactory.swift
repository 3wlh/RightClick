import Foundation

public enum RightClickRuntimeFactory {
    public static func defaultStoragePaths() -> RightClickStoragePaths {
        RightClickStoragePaths.defaultForCurrentProcess()
    }

    public static func makeActionRunner(paths: RightClickStoragePaths) -> ActionRunner {
        let configProvider = FileBackedRightClickConfigProvider(paths: paths)
        let operationLog = JSONLineOperationLog(url: paths.operationLogURL)
        let cutClipboard = FileBackedCutClipboardStore(url: paths.cutClipboardURL)

        #if canImport(AppKit)
        let opener = NSWorkspaceURLOpener()
        let pathClipboard: PathClipboardWriting = NSPasteboardPathClipboard()
        #else
        let opener = RecordingURLOpener()
        let pathClipboard: PathClipboardWriting = InMemoryPathClipboard()
        #endif

        return ActionRunner(
            configProvider: configProvider,
            operationLog: operationLog,
            cutClipboard: cutClipboard,
            pathClipboard: pathClipboard,
            urlOpener: opener,
            developerAppOpener: opener
        )
    }
}
