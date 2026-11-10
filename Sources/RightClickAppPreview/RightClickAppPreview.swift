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

/// 菜单栏快捷菜单显隐偏好；默认显示，关闭后从启动台打开 App 直达设置窗口。
enum MenuBarQuickMenuPreference {
    static let storageKey = "com.local.rightclick.settings.menubar.quickMenuEnabled"

    static var isEnabled: Bool {
        (UserDefaults.standard.object(forKey: storageKey) as? Bool) ?? true
    }
}

@main
struct RightClickAppPreview: App {
    @NSApplicationDelegateAdaptor(RightClickAppDelegate.self) private var appDelegate

    var body: some Scene {
        // LSUIElement 壳：状态栏快捷菜单与设置窗口均由 AppKit 控制器管理，
        // 这里只保留一个不可见的占位场景。
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class RightClickAppDelegate: NSObject, NSApplicationDelegate {
    private let quickMenuController = MenuBarQuickMenuController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 尽早完成配置加载与 Finder 扩展注册调度。
        _ = SettingsViewModel.shared
        applyApplicationMenuTitle()

        // 设置页开关实时生效：偏好变化时同步状态栏快捷菜单显隐。
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleUserDefaultsDidChange),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
        quickMenuController.syncVisibility()

        // 隐藏菜单栏快捷菜单时，从启动台首次拉起 App 直接进入设置窗口；
        // 开机登录项自启（由 loginwindow 拉起）时不弹窗，保持静默后台运行。
        if !MenuBarQuickMenuPreference.isEnabled && !isLaunchedByLoginItem {
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

    // LSUIElement 应用没有 Dock 图标；快捷菜单隐藏时，再次从启动台打开
    // 会触发 reopen 事件，这里负责把设置窗口前置。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !MenuBarQuickMenuPreference.isEnabled {
            SettingsWindowController.shared.showSettings()
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @objc private func handleUserDefaultsDidChange() {
        quickMenuController.syncVisibility()
    }

    private func applyApplicationMenuTitle() {
        NSApplication.shared.mainMenu?.items.first?.title = AppMetadata.displayName
    }
}

/// 状态栏快捷菜单（原 SwiftUI MenuBarExtra 的 AppKit 等价实现）。
/// 改用 NSStatusItem 直接管理，以支持在设置页开关后运行时即时显隐。
@MainActor
final class MenuBarQuickMenuController: NSObject {
    private var statusItem: NSStatusItem?

    func syncVisibility() {
        if MenuBarQuickMenuPreference.isEnabled {
            showQuickMenu()
        } else {
            hideQuickMenu()
        }
    }

    private func showQuickMenu() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "contextualmenu.and.cursorarrow",
            accessibilityDescription: AppMetadata.displayName
        )
        item.menu = buildMenu()
        statusItem = item
    }

    private func hideQuickMenu() {
        guard let statusItem else { return }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(makeItem(title: "打开设置", action: #selector(openSettingsAction)))
        menu.addItem(makeItem(title: "修复右键菜单...", action: #selector(repairContextMenuAction)))
        menu.addItem(.separator())
        menu.addItem(makeItem(title: "退出 \(AppMetadata.displayName)", action: #selector(quitAction)))
        return menu
    }

    private func makeItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func openSettingsAction() {
        SettingsWindowController.shared.showSettings()
    }

    @objc private func repairContextMenuAction() {
        let viewModel = SettingsViewModel.shared
        viewModel.repairFinderContextMenu(restartFinder: true, userInitiated: true)
        viewModel.selectedSection = .onboarding
        SettingsWindowController.shared.showSettings()
    }

    @objc private func quitAction() {
        NSApplication.shared.terminate(nil)
    }
}

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private static let frameAutosaveName = "RightClickSettingsWindow"

    private var window: NSWindow?

    func showSettings() {
        let window = ensureWindow()
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
        window.contentView = NSHostingView(rootView: SettingsWindowRootView(viewModel: SettingsViewModel.shared))
        let restoredFrame = window.setFrameUsingName(Self.frameAutosaveName)
        window.setFrameAutosaveName(Self.frameAutosaveName)
        if !restoredFrame {
            window.center()
        }
        self.window = window
        return window
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
