import AppKit
import RightClickCore
import SwiftUI
import UniformTypeIdentifiers

enum AppMetadata {
    static let displayName = "RightClick"
    static let releasesPageURL = URL(string: "https://github.com/3wlh/RightClick/releases")!
    static let latestReleaseAPIURL = URL(string: "https://api.github.com/repos/3wlh/RightClick/releases/latest")!

    static var currentVersion: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return (info["CFBundleShortVersionString"] as? String)
            .flatMap { $0.isEmpty ? nil : $0 } ?? "0.0.0-dev"
    }

    static var versionText: String {
        "版本 \(currentVersion)"
    }
}

enum AppThemePreference: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    static let storageKey = "com.local.rightclick.settings.theme"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }

    var systemImage: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

@main
struct RightClickAppPreview: App {
    @NSApplicationDelegateAdaptor(RightClickAppDelegate.self) private var appDelegate

    var body: some Scene {
        // 设置窗口由 AppKit 控制器管理，这里只保留一个不可见的占位场景。
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class RightClickAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 启动阶段只保证配置文件存在并检查扩展注册，不创建设置页状态，
        // 避免后台常驻时把 SwiftUI 视图树与配置状态一直留在内存里。
        ensureConfigurationFileExists()
        FinderExtensionStartupRegistrar.registerIfNeeded()
        applyApplicationMenuTitle()

        // 设置窗口是 App 唯一的前台界面：非登录项启动（启动台/双击）总是直接进入设置窗口，
        // 关闭窗口即退出进程；开机登录项自启（由 loginwindow 拉起）时不弹窗，保持静默后台运行。
        if !isLaunchedByLoginItem {
            SettingsWindowController.shared.showSettings()
        }
    }

    // ：通过当前启动 AppleEvent 的发送方区分启动来源
    // 登录项自启的发送方是 loginwindow，启动台/手动打开则是 Launchpad、Finder 等。
    private var isLaunchedByLoginItem: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              let senderPID = event.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr))?.int32Value
        else { return false }
        return NSRunningApplication(processIdentifier: senderPID)?.bundleIdentifier == "com.apple.loginwindow"
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        applyApplicationMenuTitle()
    }

    // 再次从启动台或 Dock 打开 App 会触发 reopen 事件，
    // 这里负责把设置窗口前置。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindowController.shared.showSettings()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // Finder 扩展通过 rightclick://run-command 唤起 App 执行命令，
    // 沙盒扩展无法发送携带 userInfo 的分布式通知，URL Scheme 是可靠的替代通道。
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if let shareRequest = AirDropShareURL.request(from: url) {
                AirDropShareController.shared.share(paths: shareRequest.paths)
                continue
            }
            guard let request = CommandRunURL.request(from: url) else {
                continue
            }
            CommandRunController.shared.execute(request: request)
        }
    }

    private func applyApplicationMenuTitle() {
        NSApplication.shared.mainMenu?.items.first?.title = AppMetadata.displayName
    }

    /// 启动阶段只确保配置文件存在，不创建设置页状态。
    private func ensureConfigurationFileExists() {
        do {
            _ = try ConfigurationBootstrapper().bootstrap(paths: .defaultForCurrentProcess())
        } catch {
            // 生成失败时保持静默；设置页打开后会再次尝试并展示错误。
        }
    }
}

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()
    private static let frameAutosaveName = "RightClickSettingsWindow"

    private var window: NSWindow?
    private var hostingView: NSHostingView<SettingsWindowRootView>?

    func showSettings() {
        let window = ensureWindow()
        installContentViewIfNeeded(on: window)
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func ensureWindow() -> NSWindow {
        if let window {
            return window
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1448, height: 980),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(AppMetadata.displayName) 设置"
        window.minSize = NSSize(width: 1180, height: 760)
        window.isReleasedWhenClosed = false
        window.delegate = self
        let restoredFrame = window.setFrameUsingName(Self.frameAutosaveName)
        window.setFrameAutosaveName(Self.frameAutosaveName)
        if !restoredFrame {
            window.center()
        }
        self.window = window
        return window
    }

    /// 关闭窗口后释放 SwiftUI 视图树，只保留空壳 NSWindow 用于恢复窗口位置。
    private func installContentViewIfNeeded(on window: NSWindow) {
        guard hostingView == nil else {
            return
        }
        let hostingView = NSHostingView(
            rootView: SettingsWindowRootView(viewModel: SettingsViewModel.shared)
        )
        self.hostingView = hostingView
        window.contentView = hostingView
    }

    /// 关闭前先拦下未保存的修改，避免用户误关窗口丢配置。
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === window else {
            return true
        }
        guard SettingsViewModel.shared.hasUnsavedChanges else {
            return true
        }

        let alert = NSAlert()
        alert.messageText = "有未保存的修改"
        alert.informativeText = "关闭设置窗口会退出 \(AppMetadata.displayName)，当前未保存的修改将丢失。"
        alert.addButton(withTitle: "放弃修改并退出")
        alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow, closingWindow === window else {
            return
        }
        hostingView = nil
        closingWindow.contentView = nil
        // 设置窗口关闭后直接退出进程，避免后台常驻占用内存。
        NSApplication.shared.terminate(nil)
    }
}

/// 承载设置窗口内容，保留原有主题偏好与布局约束。
struct SettingsWindowRootView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @AppStorage(AppThemePreference.storageKey) private var themeRawValue = AppThemePreference.system.rawValue

    var body: some View {
        SettingsRootView(viewModel: viewModel)
            .frame(minWidth: 1180, idealWidth: 1448, maxWidth: .infinity, minHeight: 760, idealHeight: 980, maxHeight: .infinity)
            .preferredColorScheme(AppThemePreference(rawValue: themeRawValue)?.colorScheme)
    }
}

/// 启动阶段只做 Finder 扩展注册检查，不创建 SettingsViewModel，
/// 让后台常驻状态保持轻量；设置页首次打开时还会再校验一次以展示失败横幅。
@MainActor
enum FinderExtensionStartupRegistrar {
    private static var isRunning = false

    static func registerIfNeeded() {
        guard !isRunning, let appexURL = bundledFinderExtensionURL() else {
            return
        }

        let signature = FinderExtensionInstallSignature.make(
            appexURL: appexURL,
            hostBundleURL: Bundle.main.bundleURL
        )
        guard UserDefaults.standard.string(forKey: FinderExtensionSetupDefaults.completedSignatureKey) != signature else {
            return
        }

        isRunning = true
        let request = SystemMaintenanceRequest(
            task: .repairFinderContextMenu,
            finderExtensionPath: appexURL.path
        )
        RightClickActionRunnerXPCClient().performMaintenance(request) { result in
            let didSucceed: Bool
            switch result {
            case .success(let maintenanceResult):
                didSucceed = maintenanceResult.isSuccess
            case .failure:
                didSucceed = false
            }
            Task { @MainActor in
                isRunning = false
                if didSucceed {
                    UserDefaults.standard.set(
                        signature,
                        forKey: FinderExtensionSetupDefaults.completedSignatureKey
                    )
                }
            }
        }
    }

    private static func bundledFinderExtensionURL() -> URL? {
        let pluginName = "RightClickFinderExtension.appex"
        let candidates = [
            Bundle.main.builtInPlugInsURL?.appendingPathComponent(pluginName),
            Bundle.main.bundleURL
                .appendingPathComponent("Contents")
                .appendingPathComponent("PlugIns")
                .appendingPathComponent(pluginName)
        ].compactMap { $0 }

        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }
}
