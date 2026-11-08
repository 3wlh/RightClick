import AppKit
import SwiftUI

/// 用 NSScrollView 承载 SwiftUI 内容，强制使用常驻（legacy）滚动条。
/// SwiftUI 的 ScrollView 会跟随系统“自动隐藏滚动条”设置，无法单独覆盖，因此这里改用 AppKit 实现。
struct AppKitScrollContainer<Content: View>: NSViewRepresentable {
    @ViewBuilder var content: Content

    func makeNSView(context: Context) -> ScrollHostView {
        ScrollHostView(content: AnyView(content))
    }

    func updateNSView(_ nsView: ScrollHostView, context: Context) {
        nsView.updateContent(AnyView(content))
    }
}

final class ScrollHostView: NSScrollView {
    private let hostingView: NSHostingView<AnyView>

    init(content: AnyView) {
        hostingView = NSHostingView(rootView: content)
        super.init(frame: .zero)

        drawsBackground = false
        borderType = .noBorder
        hasVerticalScroller = true
        hasHorizontalScroller = false
        autohidesScrollers = false
        scrollerStyle = .legacy
        verticalScrollElasticity = .allowed

        hostingView.frame = NSRect(x: 0, y: 0, width: 1, height: 1)
        documentView = hostingView
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateContent(_ content: AnyView) {
        hostingView.rootView = content
        needsLayout = true
    }

    override func layout() {
        super.layout()

        let width = max(contentSize.width, 1)
        if hostingView.frame.width != width {
            hostingView.frame.size.width = width
            hostingView.layoutSubtreeIfNeeded()
        }
        let height = max(hostingView.fittingSize.height, contentSize.height)
        if hostingView.frame.height != height {
            hostingView.frame = NSRect(x: 0, y: 0, width: width, height: height)
        }
        // 内容未超出可视区域时复位到顶部，避免切换页面后残留旧的滚动偏移。
        if hostingView.frame.height <= contentSize.height,
           contentView.bounds.origin != .zero {
            contentView.scroll(to: .zero)
            reflectScrolledClipView(contentView)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scrollerStyle = .legacy
        autohidesScrollers = false
        hasVerticalScroller = true
        tile()
    }
}
