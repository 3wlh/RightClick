import AppKit

/// 主 App 侧展示 AirDrop 分享面板；Finder 扩展通过 rightclick://airdrop 唤起。
///
/// RightClick 是菜单栏（accessory）应用，AirDrop 面板需要普通应用激活策略才能正常展示，
/// 因此分享期间临时切换为 regular，分享结束后恢复。
@MainActor
final class AirDropShareController: NSObject, NSSharingServiceDelegate {
    static let shared = AirDropShareController()

    /// 分享过程中保留 service 引用，面板关闭前不能被释放。
    private var service: NSSharingService?
    private var previousActivationPolicy: NSApplication.ActivationPolicy?

    func share(paths: [String]) {
        let urls = paths.map { URL(fileURLWithPath: $0) }
        guard !urls.isEmpty else {
            return
        }
        guard let service = NSSharingService(named: .sendViaAirDrop) else {
            NSLog("RightClick AirDrop service is unavailable")
            return
        }

        self.service = service
        service.delegate = self

        if NSApp.activationPolicy() != .regular {
            previousActivationPolicy = NSApp.activationPolicy()
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)

        // URL 唤起时 App 可能尚未完全激活，稍等再展示分享面板。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            service.perform(withItems: urls)
        }
    }

    private func finish() {
        service = nil
        if let policy = previousActivationPolicy {
            NSApp.setActivationPolicy(policy)
            previousActivationPolicy = nil
        }
    }

    nonisolated func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        Task { @MainActor in self.finish() }
    }

    nonisolated func sharingService(
        _ sharingService: NSSharingService,
        didFailToShareItems items: [Any],
        error: any Error
    ) {
        Task { @MainActor in self.finish() }
    }
}
