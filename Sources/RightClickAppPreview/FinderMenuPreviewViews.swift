import AppKit
import RightClickCore
import SwiftUI
import UniformTypeIdentifiers

struct MenuIconView: View {
    let icon: MenuIconDescriptor
    var tint: Color = SettingsTheme.muted
    var isHighlighted = false
    var size: CGFloat = 16
    var font: Font = .caption.weight(.semibold)

    var body: some View {
        Group {
            if case let .systemSymbol(systemImage) = icon {
                Image(systemName: systemImage)
                    .font(font)
                    .foregroundStyle(isHighlighted ? .white : tint)
            } else if let image = icon.resolvedNSImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: icon.fallbackSystemImage)
                    .font(font)
                    .foregroundStyle(isHighlighted ? .white : tint)
            }
        }
        .frame(width: size, height: size)
    }
}

struct FinderMenuItem: Identifiable {
    let id: String
    let title: String
    var icon: MenuIconDescriptor? = nil
    var tint: Color = SettingsTheme.muted
    var isHighlighted = false
    var hasSubmenu = false
    var startsSection = false

    init(
        title: String,
        systemImage: String? = nil,
        icon: MenuIconDescriptor? = nil,
        tint: Color = SettingsTheme.muted,
        isHighlighted: Bool = false,
        hasSubmenu: Bool = false,
        startsSection: Bool = false,
        id: String? = nil
    ) {
        self.title = title
        self.icon = icon ?? systemImage.map(MenuIconDescriptor.systemSymbol)
        self.tint = tint
        self.isHighlighted = isHighlighted
        self.hasSubmenu = hasSubmenu
        self.startsSection = startsSection
        self.id = id ?? "\(title)|\(Self.iconIdentity(self.icon))|\(isHighlighted)|\(hasSubmenu)|\(startsSection)"
    }

    private static func iconIdentity(_ icon: MenuIconDescriptor?) -> String {
        guard let icon else {
            return "none"
        }
        switch icon {
        case .systemSymbol(let name):
            return "system:\(name)"
        case .appBundleIdentifier(let bundleIdentifier):
            return "app:\(bundleIdentifier)"
        case .filePath(let path):
            return "path:\(path)"
        case .fileExtension(let fileExtension):
            return "extension:\(fileExtension)"
        case .folder:
            return "folder"
        }
    }
}

enum FinderPreviewRootMenu {
    static func standardContainerMenu(highlighting item: FinderMenuItem) -> [FinderMenuItem] {
        var highlightedItem = item
        highlightedItem.startsSection = true

        return [
            FinderMenuItem(title: "打开"),
            FinderMenuItem(title: "打开方式", hasSubmenu: true),
            FinderMenuItem(title: "移到废纸篓", startsSection: true),
            FinderMenuItem(title: "显示简介", startsSection: true),
            FinderMenuItem(title: "重新命名"),
            FinderMenuItem(title: "压缩 “示例文件夹”"),
            FinderMenuItem(title: "复制"),
            FinderMenuItem(title: "制作替身"),
            FinderMenuItem(title: "快速查看"),
            highlightedItem,
            FinderMenuItem(title: "服务", hasSubmenu: true, startsSection: true)
        ]
    }
}

extension MenuIconDescriptor {
    /// 图标解析结果缓存，避免滚动时反复访问 Workspace 造成卡顿。
    nonisolated(unsafe) private static let resolvedImageCache = NSCache<NSString, NSImage>()

    private var resolvedImageCacheKey: String {
        switch self {
        case .systemSymbol(let name):
            return "symbol:\(name)"
        case .appBundleIdentifier(let bundleIdentifier):
            return "app:\(bundleIdentifier)"
        case .filePath(let path):
            return "path:\(path)"
        case .fileExtension(let fileExtension):
            return "ext:\(fileExtension.lowercased())"
        case .folder:
            return "folder"
        }
    }

    var fallbackSystemImage: String {
        switch self {
        case .systemSymbol(let name):
            return name
        case .appBundleIdentifier:
            return "app.fill"
        case .filePath:
            return "folder.fill"
        case .fileExtension:
            return "doc"
        case .folder:
            return "folder.fill"
        }
    }

    var resolvedNSImage: NSImage? {
        let key = resolvedImageCacheKey as NSString
        if let cached = Self.resolvedImageCache.object(forKey: key) {
            return cached
        }

        let image: NSImage?
        switch self {
        case .systemSymbol:
            return nil
        case .appBundleIdentifier(let bundleIdentifier):
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
                image = NSWorkspace.shared.icon(forFile: appURL.path)
            } else {
                image = NSWorkspace.shared.icon(for: .applicationBundle)
            }
        case .filePath(let path):
            if FileManager.default.fileExists(atPath: path) {
                image = NSWorkspace.shared.icon(forFile: path)
            } else if !URL(fileURLWithPath: path).pathExtension.isEmpty {
                image = nsImageForFileExtension(URL(fileURLWithPath: path).pathExtension)
            } else {
                image = NSWorkspace.shared.icon(for: .folder)
            }
        case .fileExtension(let fileExtension):
            image = nsImageForFileExtension(fileExtension)
        case .folder:
            image = NSWorkspace.shared.icon(for: .folder)
        }
        image?.size = NSSize(width: 48, height: 48)
        if let image {
            Self.resolvedImageCache.setObject(image, forKey: key)
        }
        return image
    }

    private func nsImageForFileExtension(_ fileExtension: String) -> NSImage {
        let normalized = fileExtension.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let contentType = UTType(filenameExtension: normalized) ?? .data
        return NSWorkspace.shared.icon(for: contentType)
    }
}

struct FinderMenuPreview: View {
    let title: String?
    let caption: String?
    let rootItems: [FinderMenuItem]
    let submenuTitle: String?
    let submenuItems: [FinderMenuItem]
    var isFramed = true

    var body: some View {
        if isFramed {
            DesignPanel {
                previewBody
            }
        } else {
            previewBody
        }
    }

    private var previewBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            if title != nil || caption != nil {
                VStack(alignment: .leading, spacing: 6) {
                    if let title {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(SettingsTheme.ink)
                    }
                    if let caption {
                        Text(caption)
                            .font(.callout)
                            .foregroundStyle(SettingsTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            // 宽度足够时（如页面底部的整行预览）根菜单与子菜单并排；
            // 窄容器内自动退化为上下排列，避免被裁剪。
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 10) {
                    FinderMenuBox(items: rootItems)

                    if !submenuItems.isEmpty {
                        FinderMenuBox(title: submenuTitle, items: submenuItems)
                    }
                }

                VStack(spacing: 10) {
                    FinderMenuBox(items: rootItems)

                    if !submenuItems.isEmpty {
                        FinderMenuBox(title: submenuTitle, items: submenuItems)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }
}

struct FinderMenuBox: View {
    var title: String?
    let items: [FinderMenuItem]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if item.startsSection && index > 0 {
                    Divider()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                }

                FinderMenuRow(item: item)
            }
        }
        .padding(.vertical, 8)
        .frame(width: 228)
        .background(SettingsTheme.menuBackground, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(SettingsTheme.hairline))
        .shadow(color: SettingsTheme.menuShadow, radius: 18, x: 0, y: 12)
    }
}

struct FinderMenuRow: View {
    let item: FinderMenuItem

    var body: some View {
        HStack(spacing: 9) {
            if let icon = item.icon {
                MenuIconView(
                    icon: icon,
                    tint: item.tint,
                    isHighlighted: item.isHighlighted,
                    size: 17,
                    font: .system(size: 13, weight: .semibold)
                )
            }

            Text(item.title)
                .font(.system(size: 13))
                .foregroundStyle(item.isHighlighted ? .white : SettingsTheme.ink)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            if item.hasSubmenu {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(item.isHighlighted ? .white : SettingsTheme.muted)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 26)
        .background(
            item.isHighlighted ? SettingsTheme.accent : Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
        .padding(.horizontal, item.isHighlighted ? 5 : 0)
    }
}

