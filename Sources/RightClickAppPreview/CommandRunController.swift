import AppKit
import Darwin
import RightClickCore

/// 接收 Finder 扩展转发的命令请求，在主 App 进程中执行。
@MainActor
final class CommandRunController {
    static let shared = CommandRunController()

    /// 静默运行中的进程，需要持有引用以便超时终止与结束回收。
    private var silentProcesses: [ObjectIdentifier: Process] = [:]

    func execute(request: CommandRunRequest) {
        let provider = FileBackedRightClickConfigProvider(paths: .defaultForCurrentProcess())

        guard
            let config = try? provider.loadConfig(),
            let action = config.actions.first(where: { $0.id == request.actionID }),
            let templateID = action.payload.commandTemplateID,
            let template = config.commandTemplates.first(where: { $0.id == templateID })
        else {
            reportFailure("找不到对应的命令模板或菜单动作")
            return
        }

        let directory = resolvedWorkingDirectory(for: template, context: request.context)
        let expandedCommand = CommandPlaceholder.expand(
            template.command,
            selectedItems: request.context.selectedItems,
            fallbackDirectory: directory
        )
        let environment = CommandEnvironment.parse(template.environment)

        if template.runInTerminal {
            runInTerminal(
                title: action.title,
                command: expandedCommand,
                directory: directory,
                environment: environment
            )
        } else {
            runSilently(
                command: expandedCommand,
                directory: directory,
                environment: environment,
                timeoutSeconds: template.timeoutSeconds
            )
        }
    }

    private func resolvedWorkingDirectory(for template: CommandTemplate, context: FinderContext) -> URL {
        switch template.workingDirectory {
        case .currentDirectory:
            return context.targetDirectory
        case .selectedItemDirectory:
            return context.selectedItems.first?.deletingLastPathComponent() ?? context.targetDirectory
        }
    }

    /// 通过 Apple Events 让 Terminal 直接执行命令，不生成脚本文件。
    private func runInTerminal(title: String, command: String, directory: URL, environment: [String: String]) {
        // 清理旧版本遗留的 .command 脚本，避免继续堆积。
        let legacyDirectory = RightClickStoragePaths.defaultForCurrentProcess()
            .baseURL
            .appendingPathComponent("terminal-scripts", isDirectory: true)
        try? FileManager.default.removeItem(at: legacyDirectory)

        let normalizedCommand = command
            .replacingOccurrences(of: "\r\n", with: "; ")
            .replacingOccurrences(of: "\n", with: "; ")
        let exports = environment
            .sorted { $0.key < $1.key }
            .map { "export \($0.key)=\(shellQuoted($0.value))" }
            .joined(separator: "; ")

        // Terminal 的脚本接口没有「工作目录」参数，先在窗口内切目录并清屏，
        // 再单独把命令输入到同一个 shell，界面上就只看到在目标目录执行命令。
        var setupCommands = ["cd \(shellQuoted(directory.path))"]
        if !exports.isEmpty {
            setupCommands.append(exports)
        }
        setupCommands.append("clear")
        let setup = setupCommands.joined(separator: "; ")

        let source = """
        tell application "Terminal"
            activate
            set targetTab to do script "\(escapeForAppleScriptString(setup))"
            delay 0.2
            repeat 20 times
                if not (busy of targetTab) then exit repeat
                delay 0.05
            end repeat
            do script "\(escapeForAppleScriptString(normalizedCommand))" in targetTab
            set custom title of targetTab to "\(escapeForAppleScriptString(title))"
        end tell
        """

        var errorInfo: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&errorInfo)

        if let errorInfo {
            let message = (errorInfo[NSAppleScript.errorMessage] as? String) ?? "未知错误"
            reportFailure("无法在终端中执行命令：\(message)")
        }
    }

    /// 后台静默执行：丢弃标准输出与标准错误，不弹窗口。
    private func runSilently(
        command: String,
        directory: URL,
        environment: [String: String],
        timeoutSeconds: Int
    ) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.currentDirectoryURL = directory
        if !environment.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        let identifier = ObjectIdentifier(process)
        silentProcesses[identifier] = process
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.silentProcesses.removeValue(forKey: identifier)
            }
        }

        do {
            try process.run()
        } catch {
            silentProcesses.removeValue(forKey: identifier)
            reportFailure("无法启动命令：\(error.localizedDescription)")
            return
        }

        scheduleTimeout(for: process, seconds: max(5, min(600, timeoutSeconds)))
    }

    /// 超时先 SIGTERM，2 秒后仍未退出则 SIGKILL。
    private func scheduleTimeout(for process: Process, seconds: Int) {
        DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(seconds)) {
            guard process.isRunning else {
                return
            }
            process.terminate()

            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                guard process.isRunning else {
                    return
                }
                kill(process.processIdentifier, SIGKILL)
            }
        }
    }

    private func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func escapeForAppleScriptString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func reportFailure(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "命令执行失败"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}
