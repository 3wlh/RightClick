import Foundation
import RightClickCore

final class ActionRunnerServiceDelegate: NSObject, NSXPCListenerDelegate {
    private let exportedObject: RightClickActionRunnerXPCAdapter

    init(exportedObject: RightClickActionRunnerXPCAdapter) {
        self.exportedObject = exportedObject
    }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: RightClickActionRunnerXPCProtocol.self)
        connection.exportedObject = exportedObject
        connection.resume()
        return true
    }
}

let paths: RightClickStoragePaths
if let override = ProcessInfo.processInfo.environment["RIGHTCLICKPRO_STORAGE_PATH"] {
    paths = RightClickStoragePaths(baseURL: URL(fileURLWithPath: override))
} else {
    paths = RightClickStoragePaths.defaultForCurrentProcess()
}

let runner = RightClickRuntimeFactory.makeActionRunner(paths: paths)
let adapter = RightClickActionRunnerXPCAdapter(runner: runner)
let delegate = ActionRunnerServiceDelegate(exportedObject: adapter)
let listener = NSXPCListener.service()
listener.delegate = delegate
listener.resume()

RunLoop.main.run()
