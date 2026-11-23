import AppKit

/// 主 App 侧展示 AirDrop 分享面板；Finder 扩展通过 rightclick://airdrop 唤起。
///
/// App 默认以后台方式运行以不占 Dock，分享面板由系统呈现，
/// 这里只把 App 提到前台，不切换激活策略。
@MainActor
final class AirDropShareController: NSObject, NSSharingServiceDelegate {
    static let shared = AirDropShareController()

    /// 分享过程中保留 service 引用，面板关闭前不能被释放。
    private var service: NSSharingService?

    /// 分享结束（完成、失败或无法展示）后回调，供 App 判断是否可以在没有窗口时退出。
    var onFinished: (() -> Void)?

    func share(paths: [String]) {
        let urls = paths.map { URL(fileURLWithPath: $0) }
        guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else {
            NSLog("RightClick AirDrop service is unavailable")
            finish()
            return
        }

        self.service = service
        service.delegate = self
        NSApp.activate(ignoringOtherApps: true)

        // URL 唤起时 App 可能尚未完全激活，稍等再展示分享面板。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            service.perform(withItems: urls)
        }
    }

    private func finish() {
        service = nil
        let handler = onFinished
        onFinished = nil
        handler?()
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
