import AppKit
import RightClickCore
import SwiftUI
import UniformTypeIdentifiers

struct CommandListView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @State private var editingDraft: CommandTemplateDraft?
    @State private var draggingTemplateID: String?

    var body: some View {
        let templates = viewModel.config.commandTemplates

        DesignPageScroll {
            DesignPanel(padding: 0) {
                LazyVStack(spacing: 0) {
                    CommandTableHeader()

                    if let first = templates.first {
                        Color.clear
                            .frame(height: 14)
                            .contentShape(Rectangle())
                            .onDrop(
                                of: [UTType.text],
                                delegate: ReorderDropDelegate(
                                    targetID: first.id,
                                    rowHeight: 0,
                                    draggingID: $draggingTemplateID
                                ) { sourceID, targetID, _ in
                                    viewModel.reorderCommandTemplates(
                                        templates.map(\.id),
                                        moving: sourceID,
                                        targetID: targetID,
                                        placeAfter: false
                                    )
                                }
                            )
                    }

                    if templates.isEmpty {
                        EmptyStateRow(title: "暂无命令模板", systemImage: "terminal")
                    } else {
                        ForEach(Array(templates.enumerated()), id: \.element.id) { index, template in
                            CommandTableRow(
                                template: template,
                                viewModel: viewModel,
                                onEdit: {
                                    editingDraft = CommandTemplateDraft(template: template)
                                }
                            )
                            .contentShape(Rectangle())
                            .opacity(draggingTemplateID == template.id ? 0.5 : 1)
                            .onDrag {
                                draggingTemplateID = template.id
                                return NSItemProvider(object: template.id as NSString)
                            }
                            .onDrop(
                                of: [UTType.text],
                                delegate: ReorderDropDelegate(
                                    targetID: template.id,
                                    rowHeight: 52,
                                    draggingID: $draggingTemplateID
                                ) { sourceID, targetID, placeAfter in
                                    viewModel.reorderCommandTemplates(
                                        templates.map(\.id),
                                        moving: sourceID,
                                        targetID: targetID,
                                        placeAfter: placeAfter
                                    )
                                }
                            )
                            if index < templates.count - 1 {
                                Divider()
                            }
                        }
                    }

                    if let last = templates.last {
                        Color.clear
                            .frame(height: 14)
                            .contentShape(Rectangle())
                            .onDrop(
                                of: [UTType.text],
                                delegate: ReorderDropDelegate(
                                    targetID: last.id,
                                    rowHeight: 0,
                                    draggingID: $draggingTemplateID
                                ) { sourceID, targetID, _ in
                                    viewModel.reorderCommandTemplates(
                                        templates.map(\.id),
                                        moving: sourceID,
                                        targetID: targetID,
                                        placeAfter: true
                                    )
                                }
                            )
                    }
                }
            }

            CommandHintBanner()

            CommandMenuPreviewPanel(items: commandPreviewItems)
        }
        .sheet(item: $editingDraft) { draft in
            CommandTemplateEditorSheet(draft: draft) { savedDraft in
                viewModel.upsertCommandTemplate(savedDraft.makeTemplate(), replacing: savedDraft.originalID)
                editingDraft = nil
            } onCancel: {
                editingDraft = nil
            }
        }
        .onChange(of: viewModel.commandTemplateAddRequest) { _, _ in
            editingDraft = CommandTemplateDraft()
        }
    }

    private var commandPreviewItems: [FinderMenuItem] {
        let enabledActions = viewModel.config.actions
            .filter { $0.kind == .runCommand && $0.isEnabled }
            .sorted { $0.order < $1.order }

        return enabledActions.compactMap { action -> FinderMenuItem? in
            guard
                let templateID = action.payload.commandTemplateID,
                let template = viewModel.config.commandTemplates.first(where: { $0.id == templateID })
            else {
                return nil
            }

            return FinderMenuItem(
                title: action.title,
                icon: commandIconDescriptor(for: template),
                tint: SettingsTheme.accent,
                id: action.id
            )
        }
    }
}

struct CommandTableHeader: View {
    var body: some View {
        HStack(spacing: 16) {
            Text("排序")
                .fixedSize()
                .frame(width: 18, alignment: .center)
            Text("模板名称").frame(maxWidth: .infinity, alignment: .leading)
            Text("命令").frame(width: 240, alignment: .leading)
            Text("工作目录").frame(width: 120, alignment: .leading)
            Text("启用").frame(width: 84, alignment: .center)
            Text("操作").frame(width: 72, alignment: .center)
        }
        .settingsTableHeaderStyle()
    }
}

struct CommandTableRow: View {
    let template: CommandTemplate
    @ObservedObject var viewModel: SettingsViewModel
    let onEdit: () -> Void

    private var matchingAction: RightClickAction? {
        viewModel.config.actions.first {
            $0.kind == .runCommand && $0.payload.commandTemplateID == template.id
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(SettingsTheme.muted)
                .frame(width: 18)
                .help("拖动调整顺序")

            Button(action: onEdit) {
                HStack(spacing: 12) {
                    CommandIconTile(template: template)
                    Text(templateDisplayTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SettingsTheme.ink)
                        .lineLimit(1)
                }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(template.command)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(SettingsTheme.muted)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 240, alignment: .leading)
                .help(template.command)

            Text(template.workingDirectory.displayName)
                .font(.system(size: 13))
                .foregroundStyle(SettingsTheme.muted)
                .lineLimit(1)
                .frame(width: 120, alignment: .leading)

            Toggle("", isOn: Binding(
                get: { matchingAction?.isEnabled ?? false },
                set: { isEnabled in
                    guard let actionID = matchingAction?.id else { return }
                    viewModel.setActionEnabled(isEnabled, actionID: actionID)
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .disabled(matchingAction == nil)
            .frame(width: 84)

            HStack(spacing: 8) {
                RowIconButton(
                    systemImage: "pencil",
                    accessibilityLabel: "编辑 \(templateDisplayTitle)",
                    helpText: "编辑命令模板"
                ) {
                    onEdit()
                }

                RowIconButton(
                    systemImage: "trash",
                    accessibilityLabel: "删除 \(templateDisplayTitle)",
                    helpText: "删除命令模板",
                    tone: .destructive
                ) {
                    viewModel.deleteCommandTemplate(template)
                }
            }
            .frame(width: 72)
        }
        .padding(.horizontal, 18)
        .frame(height: 52)
        .hoverRowBackground()
        .opacity((matchingAction?.isEnabled ?? true) ? 1 : 0.55)
    }

    private var templateDisplayTitle: String {
        matchingAction?.title ?? template.title
    }
}

struct CommandIconTile: View {
    let template: CommandTemplate

    var body: some View {
        MenuIconView(
            icon: commandIconDescriptor(for: template),
            tint: SettingsTheme.accent,
            size: 20,
            font: .system(size: 18, weight: .medium)
        )
        .frame(width: 28, height: 28)
        .background(SettingsTheme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
    }
}

struct CommandMenuPreviewPanel: View {
    let items: [FinderMenuItem]

    var body: some View {
        PreviewSection(
            rootItems: rootMenuItems,
            submenuTitle: "命令模板",
            submenuItems: items.isEmpty ? [FinderMenuItem(title: "暂无启用模板")] : items
        ) {
            VStack(alignment: .leading, spacing: 8) {
                Text("右键菜单预览")
                    .font(.headline)
                    .foregroundStyle(SettingsTheme.ink)
                Text("在 Finder 中右键时，启用的命令会出现在「命令模板」子菜单中，点击后弹出实时输出窗口。")
                    .font(.callout)
                    .foregroundStyle(SettingsTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var rootMenuItems: [FinderMenuItem] {
        FinderPreviewRootMenu.standardContainerMenu(
            highlighting: FinderMenuItem(
                title: "命令模板",
                systemImage: "terminal",
                tint: SettingsTheme.accent,
                isHighlighted: true,
                hasSubmenu: true
            )
        )
    }
}

struct CommandHintBanner: View {
    var body: some View {
        SettingsHintBanner(
            icon: "lightbulb",
            title: "提示：",
            message: "命令通过 /bin/zsh -lc 执行。内置模式实时显示输出并可随时停止；系统终端模式会打开 Terminal 窗口执行。"
        )
    }
}

struct CommandTemplateDraft: Identifiable {
    let id = UUID()
    var originalID: String?
    var templateID: String
    var title: String
    var command: String
    var workingDirectory: CommandWorkingDirectory
    var environment: String
    var timeoutSeconds: Int
    var runInTerminal: Bool
    var iconSymbol: String

    init() {
        let suffix = UUID().uuidString.prefix(8).lowercased()
        originalID = nil
        templateID = "command-custom-\(suffix)"
        title = "自定义命令"
        command = ""
        workingDirectory = .currentDirectory
        environment = ""
        timeoutSeconds = 60
        runInTerminal = true
        iconSymbol = "terminal"
    }

    init(template: CommandTemplate) {
        originalID = template.id
        templateID = template.id
        title = template.title
        command = template.command
        workingDirectory = template.workingDirectory
        environment = template.environment
        timeoutSeconds = template.timeoutSeconds
        runInTerminal = template.runInTerminal
        iconSymbol = template.iconSymbol ?? ""
    }

    func makeTemplate() -> CommandTemplate {
        let icon = iconSymbol.trimmingCharacters(in: .whitespacesAndNewlines)
        return CommandTemplate(
            id: templateID.trimmingCharacters(in: .whitespacesAndNewlines),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            command: command,
            workingDirectory: workingDirectory,
            environment: environment,
            timeoutSeconds: timeoutSeconds,
            runInTerminal: runInTerminal,
            iconSymbol: icon.isEmpty ? nil : icon
        )
    }
}

struct CommandTemplateEditorSheet: View {
    @State private var draft: CommandTemplateDraft
    let onSave: (CommandTemplateDraft) -> Void
    let onCancel: () -> Void

    init(draft: CommandTemplateDraft, onSave: @escaping (CommandTemplateDraft) -> Void, onCancel: @escaping () -> Void) {
        _draft = State(initialValue: draft)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 0) {
            EditorSheetHeader(
                title: draft.originalID == nil ? "新增命令模板" : "编辑命令模板",
                subtitle: "配置 Finder 右键菜单中的命令入口，运行结果实时显示。",
                systemImage: "terminal"
            )

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    EditorTextField(
                        title: "模板 ID",
                        placeholder: "command-custom",
                        helper: "用于关联菜单动作，建议保持英文短横线命名。",
                        systemImage: "number",
                        text: $draft.templateID
                    )

                    EditorTextField(
                        title: "模板名称",
                        placeholder: "在当前目录运行脚本",
                        helper: "显示在设置页和右键菜单中的名称。",
                        prefixText: "名称",
                        text: $draft.title
                    )
                }

                EditorTextArea(
                    title: "命令",
                    helper: "支持 {{currentDirectory}} / {{selectedPath}} / {{selectedPaths}}。",
                    text: $draft.command,
                    minHeight: 96
                )

                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("工作目录")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(SettingsTheme.ink)

                        Picker("工作目录", selection: $draft.workingDirectory) {
                            ForEach(CommandWorkingDirectory.allCases, id: \.self) { directory in
                                Text(directory.displayName).tag(directory)
                            }
                        }
                        .pickerStyle(.radioGroup)
                        .labelsHidden()

                        Text(draft.workingDirectory.helperText)
                            .font(.system(size: 11))
                            .foregroundStyle(SettingsTheme.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("超时秒数")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(draft.runInTerminal ? SettingsTheme.muted : SettingsTheme.ink)

                        HStack(spacing: 8) {
                            Image(systemName: "clock")
                                .font(.system(size: 12))
                                .foregroundStyle(SettingsTheme.muted)

                            TextField("60", value: $draft.timeoutSeconds, format: .number)
                                .textFieldStyle(.plain)
                                .font(.system(size: 13))

                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .background(SettingsTheme.controlBackground, in: RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(SettingsTheme.hairline, lineWidth: 0.5)
                        )
                        .disabled(draft.runInTerminal)
                        .opacity(draft.runInTerminal ? 0.55 : 1)

                        Text(draft.runInTerminal
                            ? "系统终端运行不受超时限制，仅关闭终端开关（静默运行）时生效。"
                            : "允许 5-600 秒，超时先终止再强制结束。")
                            .font(.system(size: 11))
                            .foregroundStyle(SettingsTheme.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack(spacing: 14) {
                    Image(systemName: "terminal")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(SettingsTheme.accent)
                        .frame(width: 28, height: 28)
                        .background(SettingsTheme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))

                    VStack(alignment: .leading, spacing: 3) {
                        Text("在系统终端中运行")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(SettingsTheme.ink)
                        Text("开启后在 Terminal.app 中执行并显示结果；关闭则后台静默运行，不显示输出。")
                            .font(.system(size: 11))
                            .foregroundStyle(SettingsTheme.muted)
                    }

                    Spacer(minLength: 12)

                    Toggle("", isOn: $draft.runInTerminal)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                EditorTextArea(
                    title: "环境变量",
                    helper: "一行一个 KEY=value，支持 # 注释；会注入命令执行环境。",
                    text: $draft.environment,
                    minHeight: 96
                )
                }
                .padding(22)
            }
            .frame(maxHeight: 740)

            Divider()

            EditorSheetFooter(
                validationMessage: validationMessage,
                canSave: canSave,
                onCancel: onCancel
            ) {
                onSave(draft)
            }
        }
        .background(SettingsTheme.windowBackground)
        .frame(width: 620)
        .frame(minHeight: 600)
    }

    private var canSave: Bool {
        validationMessage == nil
    }

    private var validationMessage: String? {
        if draft.templateID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "请填写模板 ID"
        }
        if draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "请填写模板名称"
        }
        if draft.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "请填写要执行的命令"
        }
        if !draft.runInTerminal, !(5...600).contains(draft.timeoutSeconds) {
            return "超时秒数需在 5-600 秒之间"
        }
        return nil
    }
}

extension CommandWorkingDirectory {
    var displayName: String {
        switch self {
        case .currentDirectory:
            return "当前 Finder 目录"
        case .selectedItemDirectory:
            return "选中项目所在目录"
        }
    }

    var helperText: String {
        switch self {
        case .currentDirectory:
            return "在 Finder 当前打开的目录中执行命令。"
        case .selectedItemDirectory:
            return "在第一个选中项目所在的目录中执行，无选中项时回退当前目录。"
        }
    }
}

private func commandIconDescriptor(for template: CommandTemplate) -> MenuIconDescriptor {
    if let iconSymbol = template.iconSymbol, !iconSymbol.isEmpty {
        return .systemSymbol(iconSymbol)
    }
    return .systemSymbol("terminal")
}
