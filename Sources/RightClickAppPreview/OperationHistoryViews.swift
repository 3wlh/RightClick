import AppKit
import RightClickCore
import SwiftUI
import UniformTypeIdentifiers

struct OperationHistoryView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var draggingActionID: String?

    private var fileOperationActions: [RightClickAction] {
        viewModel.config.actions
            .filter { $0.group == .fileOperations || [.cut, .paste, .moveToDirectory, .copyToDirectory].contains($0.kind) }
            .sorted { $0.order < $1.order }
    }

    var body: some View {
        let actions = fileOperationActions
        let previewActions = Array(actions.prefix(8))

        DesignPageScroll {
            DesignPanel(padding: 0) {
                LazyVStack(spacing: 0) {
                    if let first = actions.first {
                        Color.clear
                            .frame(height: 14)
                            .contentShape(Rectangle())
                            .onDrop(
                                of: [UTType.text],
                                delegate: ReorderDropDelegate(
                                    targetID: first.id,
                                    rowHeight: 0,
                                    draggingID: $draggingActionID
                                ) { sourceID, targetID, _ in
                                    viewModel.reorderActions(
                                        actions.map(\.id),
                                        moving: sourceID,
                                        targetID: targetID,
                                        placeAfter: false
                                    )
                                }
                            )
                    }

                    if actions.isEmpty {
                        EmptyStateRow(title: "暂无文件操作", systemImage: "doc.on.doc")
                    } else {
                        ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                            FileOperationListRow(action: action, viewModel: viewModel)
                                .opacity(draggingActionID == action.id ? 0.5 : 1)
                                .onDrag {
                                    draggingActionID = action.id
                                    return NSItemProvider(object: action.id as NSString)
                                }
                                .onDrop(
                                    of: [UTType.text],
                                    delegate: ReorderDropDelegate(
                                        targetID: action.id,
                                        rowHeight: 56,
                                        draggingID: $draggingActionID
                                    ) { sourceID, targetID, placeAfter in
                                        viewModel.reorderActions(
                                            actions.map(\.id),
                                            moving: sourceID,
                                            targetID: targetID,
                                            placeAfter: placeAfter
                                        )
                                    }
                                )
                            if index < actions.count - 1 {
                                Divider()
                            }
                        }

                        if let last = actions.last {
                            Color.clear
                                .frame(height: 14)
                                .contentShape(Rectangle())
                                .onDrop(
                                    of: [UTType.text],
                                    delegate: ReorderDropDelegate(
                                        targetID: last.id,
                                        rowHeight: 0,
                                        draggingID: $draggingActionID
                                    ) { sourceID, targetID, _ in
                                        viewModel.reorderActions(
                                            actions.map(\.id),
                                            moving: sourceID,
                                            targetID: targetID,
                                            placeAfter: true
                                        )
                                    }
                                )
                        }
                    }
                }
            }

            PreviewSection(
                    rootItems: FinderPreviewRootMenu.standardContainerMenu(
                        highlighting: FinderMenuItem(
                            title: "文件操作",
                            systemImage: "doc.on.doc",
                            tint: SettingsTheme.accent,
                            isHighlighted: true,
                            hasSubmenu: true
                        )
                    ),
                    submenuTitle: nil,
                    submenuItems: previewActions.map {
                        FinderMenuItem(
                            title: $0.title,
                            icon: MenuIconResolver.icon(for: $0, config: viewModel.config, bookmarks: viewModel.bookmarks),
                            tint: SettingsTheme.accent,
                            id: $0.id
                        )
                    }
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("右键菜单预览")
                        .font(.headline)
                        .foregroundStyle(SettingsTheme.ink)
                    Text("在 Finder 中右键即可使用这些文件操作。")
                        .font(.callout)
                        .foregroundStyle(SettingsTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("支持剪切、粘贴、拷贝路径、隐藏、取消隐藏与直接删除文件和文件夹。")
                        .font(.caption)
                        .foregroundStyle(SettingsTheme.accent)
                }
            }
        }
    }
}

struct FileOperationListRow: View {
    let action: RightClickAction
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(SettingsTheme.muted)
                .frame(width: 18)
                .help("拖动调整顺序")

            MenuIconView(
                icon: MenuIconResolver.icon(for: action, config: viewModel.config, bookmarks: viewModel.bookmarks),
                tint: SettingsTheme.accent,
                size: 20,
                font: .callout
            )
            .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SettingsTheme.ink)
                    .lineLimit(1)
                Text(action.placement.displayName)
                    .font(.system(size: 11))
                    .foregroundStyle(SettingsTheme.muted)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            Toggle("", isOn: Binding(
                get: { action.isEnabled },
                set: { viewModel.setActionEnabled($0, actionID: action.id) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        }
        .padding(.horizontal, 14)
        .frame(height: 56)
    }
}

struct EmptyStateRow: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(SettingsTheme.muted)
            Text(title)
                .font(.callout)
                .foregroundStyle(SettingsTheme.muted)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 140)
    }
}
