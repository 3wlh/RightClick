import AppKit
import RightClickCore
import SwiftUI
import UniformTypeIdentifiers

struct DirectoryListView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var searchText = ""
    @State private var draggingBookmarkID: String?

    private var bookmarks: [DirectoryBookmark] {
        viewModel.bookmarks.bookmarks
    }

    private var filteredBookmarks: [DirectoryBookmark] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !keyword.isEmpty else { return bookmarks }
        return bookmarks.filter {
            $0.displayName.lowercased().contains(keyword) || $0.path.lowercased().contains(keyword)
        }
    }

    private var previewItems: [FinderMenuItem] {
        let enabledBookmarks = bookmarks.filter { viewModel.isDirectoryBookmarkEnabled($0.id) }
        return Array(enabledBookmarks.prefix(7)).map {
            FinderMenuItem(title: $0.displayName, icon: .filePath($0.path), tint: directoryTint(for: $0), id: $0.id)
        }
    }

    var body: some View {
        let rows = filteredBookmarks

        DesignPageScroll {
            SearchField(placeholder: "搜索目录名称或路径", text: $searchText)
                .frame(width: 270, alignment: .leading)

            DesignPanel(padding: 0) {
                LazyVStack(spacing: 0) {
                    DirectoryTableHeader()

                    if let first = rows.first {
                        Color.clear
                            .frame(height: 14)
                            .contentShape(Rectangle())
                            .onDrop(
                                of: [UTType.text],
                                delegate: ReorderDropDelegate(
                                    targetID: first.id,
                                    rowHeight: 0,
                                    draggingID: $draggingBookmarkID
                                ) { sourceID, targetID, _ in
                                    viewModel.reorderDirectoryBookmarks(
                                        rows.map(\.id),
                                        moving: sourceID,
                                        targetID: targetID,
                                        placeAfter: false
                                    )
                                }
                            )
                    }

                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, bookmark in
                        DirectoryTableRow(
                            bookmark: bookmark,
                            isEnabled: viewModel.isDirectoryBookmarkEnabled(bookmark.id),
                            onToggle: { isEnabled in
                                viewModel.setDirectoryBookmarkEnabled(isEnabled, bookmarkID: bookmark.id)
                            },
                            onEdit: {
                                viewModel.replaceDirectoryBookmarkFromPanel(bookmarkID: bookmark.id)
                            },
                            onDelete: {
                                viewModel.deleteDirectoryBookmark(bookmarkID: bookmark.id)
                            }
                        )
                        .contentShape(Rectangle())
                        .opacity(draggingBookmarkID == bookmark.id ? 0.5 : 1)
                        .onDrag {
                            draggingBookmarkID = bookmark.id
                            return NSItemProvider(object: bookmark.id as NSString)
                        }
                        .onDrop(
                            of: [UTType.text],
                            delegate: ReorderDropDelegate(
                                targetID: bookmark.id,
                                rowHeight: 52,
                                draggingID: $draggingBookmarkID
                            ) { sourceID, targetID, placeAfter in
                                viewModel.reorderDirectoryBookmarks(
                                    rows.map(\.id),
                                    moving: sourceID,
                                    targetID: targetID,
                                    placeAfter: placeAfter
                                )
                            }
                        )
                        if index < rows.count - 1 {
                            Divider()
                        }
                    }
                    if rows.isEmpty {
                        EmptyStateRow(title: "没有匹配的目录", systemImage: "folder.badge.questionmark")
                    }

                    if let last = rows.last {
                        Color.clear
                            .frame(height: 14)
                            .contentShape(Rectangle())
                            .onDrop(
                                of: [UTType.text],
                                delegate: ReorderDropDelegate(
                                    targetID: last.id,
                                    rowHeight: 0,
                                    draggingID: $draggingBookmarkID
                                ) { sourceID, targetID, _ in
                                    viewModel.reorderDirectoryBookmarks(
                                        rows.map(\.id),
                                        moving: sourceID,
                                        targetID: targetID,
                                        placeAfter: true
                                    )
                                }
                            )
                    }
                }
            }

            DirectoryHintBanner()

            DirectoryMenuPreviewPanel(items: previewItems)
        }
    }

    private func directoryTint(for bookmark: DirectoryBookmark) -> Color {
        let lowercased = bookmark.path.lowercased()
        if lowercased.contains("workspace") || lowercased.contains("project") { return .orange }
        if lowercased.contains("server") || lowercased.contains("smb://") { return SettingsTheme.accent }
        return .blue
    }
}

struct DirectoryMenuPreviewPanel: View {
    let items: [FinderMenuItem]

    var body: some View {
        PreviewSection(
            rootItems: rootMenuItems,
            submenuTitle: "常用目录",
            submenuItems: items.isEmpty ? [FinderMenuItem(title: "暂无启用目录")] : items
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Text("右键菜单预览")
                    .font(.headline)
                    .foregroundStyle(SettingsTheme.ink)
                Text("在 Finder 中右键时，启用的目录会出现在「常用目录」子菜单中。")
                    .font(.callout)
                    .foregroundStyle(SettingsTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var rootMenuItems: [FinderMenuItem] {
        FinderPreviewRootMenu.standardContainerMenu(
            highlighting: FinderMenuItem(
                title: "常用目录",
                systemImage: "folder",
                tint: .blue,
                isHighlighted: true,
                hasSubmenu: true
            )
        )
    }
}

struct DirectoryHintBanner: View {
    var body: some View {
        SettingsHintBanner(
            icon: "lightbulb",
            title: "提示：",
            message: "将最常用的目录放在前面位置，访问更高效。"
        )
    }
}

struct DirectoryTableHeader: View {
    var body: some View {
        HStack(spacing: 16) {
            Text("排序")
                .fixedSize()
                .frame(width: 18, alignment: .center)
            Text("名称").frame(width: 260, alignment: .leading)
            Text("路径").frame(maxWidth: .infinity, alignment: .leading)
            Text("启用").frame(width: 90, alignment: .center)
            Text("操作").frame(width: 104, alignment: .center)
        }
        .settingsTableHeaderStyle()
    }
}

struct DirectoryTableRow: View {
    let bookmark: DirectoryBookmark
    let isEnabled: Bool
    let onToggle: (Bool) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(SettingsTheme.muted)
                .frame(width: 18)
                .help("拖动调整顺序")

            HStack(spacing: 12) {
                MenuIconView(
                    icon: .filePath(bookmark.path),
                    tint: tint,
                    size: 24,
                    font: .system(size: 20, weight: .regular)
                )
                .frame(width: 28)
                Text(bookmark.displayName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SettingsTheme.ink)
                    .lineLimit(1)
            }
            .frame(width: 260, alignment: .leading)
            .opacity(isEnabled ? 1 : 0.48)

            Text(displayPath)
                .font(.system(size: 13))
                .foregroundStyle(SettingsTheme.muted)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            Toggle("", isOn: Binding(
                get: { isEnabled },
                set: { isEnabled in
                    onToggle(isEnabled)
                }
            ))
                .toggleStyle(.switch)
                .labelsHidden()
                .frame(width: 90)

            HStack(spacing: 8) {
                RowIconButton(
                    systemImage: "pencil",
                    accessibilityLabel: "编辑 \(bookmark.displayName)",
                    helpText: "编辑目录"
                ) {
                    onEdit()
                }

                RowIconButton(
                    systemImage: "trash",
                    accessibilityLabel: "删除 \(bookmark.displayName)",
                    helpText: "删除目录",
                    tone: .destructive
                ) {
                    onDelete()
                }
            }
            .frame(width: 104)
        }
        .padding(.horizontal, 18)
        .frame(height: 52)
        .hoverRowBackground()
    }

    private var tint: Color {
        let lowercased = bookmark.path.lowercased()
        if lowercased.contains("workspace") || lowercased.contains("project") { return .orange }
        if lowercased.contains("server") || lowercased.contains("smb://") { return SettingsTheme.accent }
        return .blue
    }

    private var displayPath: String {
        let homeCandidates = [
            "/Users/\(NSUserName())",
            FileManager.default.homeDirectoryForCurrentUser.path
        ]

        for home in homeCandidates where bookmark.path.hasPrefix(home) {
            let suffix = bookmark.path.dropFirst(home.count)
            return "~\(suffix)"
        }

        return bookmark.path
    }
}

