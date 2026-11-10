import AppKit
import RightClickCore
import SwiftUI
import UniformTypeIdentifiers

let operationDateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .medium
    return formatter
}()

extension RightClickAction {
    var managementTint: Color {
        switch group {
        case .commonDirectories, .moveToCommonDirectory, .copyToCommonDirectory:
            return .blue
        case .createFile:
            return SettingsTheme.accent
        case .developerEntrypoints:
            return SettingsTheme.accent
        case .developerTools:
            return SettingsTheme.accent
        case .fileOperations:
            return .cyan
        case .commandTemplates:
            return SettingsTheme.accent
        case .none:
            return SettingsTheme.muted
        }
    }

    var managementType: String {
        if kind == .createFile || group == .createFile {
            return "新建"
        }

        if group == .developerEntrypoints || kind == .openInApp {
            return "应用"
        }

        if kind == .runCommand || group == .commandTemplates {
            return "命令"
        }

        return "操作"
    }

    var managementSubtitle: String {
        switch kind {
        case .openDirectory:
            return "快速访问常用位置"
        case .moveToDirectory:
            return "移动所选项目到指定目录"
        case .copyToDirectory:
            return "复制所选项目到指定目录"
        case .cut:
            return "剪切所选项目到剪贴板"
        case .paste:
            return "粘贴剪贴板中的文件"
        case .createFile:
            return "在当前目录创建 \(payload.templateID ?? "文件")"
        case .openInApp:
            return "快速打开开发者常用工具"
        case .copyPath:
            return "拷贝所选项目的完整路径"
        case .hideItems:
            return "隐藏所选文件或文件夹"
        case .unhideItems:
            return "取消隐藏所选文件或文件夹"
        case .deletePermanently:
            return "永久删除所选项目，不进入废纸篓"
        case .undoOperation:
            return "撤销最近一次文件操作"
        case .airDrop:
            return "通过 AirDrop 分享所选项目"
        case .runCommand:
            return "执行自定义命令模板"
        }
    }

    var visibilityPills: [String] {
        var labels: [String] = []
        if visibility.contains(.toolbar) {
            labels.append("Finder")
        }
        if visibility.contains(.selection) {
            labels.append("文件/文件夹")
        }
        if visibility.contains(.container) {
            labels.append("桌面空白处")
        }
        return labels.isEmpty ? ["未设置"] : labels
    }
}

extension ActionKind {
    var displayName: String {
        switch self {
        case .openDirectory:
            return "打开目录"
        case .moveToDirectory:
            return "移动到目录"
        case .copyToDirectory:
            return "复制到目录"
        case .cut:
            return "剪切"
        case .paste:
            return "粘贴"
        case .createFile:
            return "新建文件"
        case .openInApp:
            return "开发者入口"
        case .copyPath:
            return "拷贝路径"
        case .hideItems:
            return "隐藏文件"
        case .unhideItems:
            return "取消隐藏"
        case .deletePermanently:
            return "直接删除"
        case .undoOperation:
            return "撤销操作"
        case .airDrop:
            return "AirDrop 分享"
        case .runCommand:
            return "命令模板"
        }
    }

}

extension ActionPlacement {
    var displayName: String {
        switch self {
        case .rootMenu:
            return "一级菜单"
        case .submenu:
            return "分组菜单"
        }
    }

    var systemImage: String {
        switch self {
        case .rootMenu:
            return "menubar.rectangle"
        case .submenu:
            return "rectangle.3.group"
        }
    }
}

struct ReorderDropDelegate: DropDelegate {
    let targetID: String
    let rowHeight: CGFloat
    @Binding var draggingID: String?
    let onMove: (String, String, Bool) -> Void

    func dropEntered(info: DropInfo) {
        guard let draggingID, draggingID != targetID else {
            return
        }
        // 鼠标落在目标行的下半部分时插到其后，保证能拖到列表最下面。
        onMove(draggingID, targetID, info.location.y > rowHeight / 2)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingID = nil
        return true
    }
}

extension MenuGroup {
    var displayName: String {
        switch self {
        case .commonDirectories:
            return "前往常用目录"
        case .moveToCommonDirectory:
            return "移动到常用目录"
        case .copyToCommonDirectory:
            return "复制到常用目录"
        case .createFile:
            return "新建文件"
        case .developerEntrypoints:
            return "应用快捷入口"
        case .developerTools:
            return "开发者工具"
        case .fileOperations:
            return "文件操作"
        case .commandTemplates:
            return "命令模板"
        }
    }

    var previewIcon: MenuIconDescriptor {
        switch self {
        case .commonDirectories, .moveToCommonDirectory, .copyToCommonDirectory:
            return .folder
        case .createFile:
            return .systemSymbol("doc.badge.plus")
        case .developerEntrypoints:
            return .systemSymbol("square.grid.2x2")
        case .developerTools:
            return .systemSymbol("chevron.left.forwardslash.chevron.right")
        case .fileOperations:
            return .systemSymbol("doc.on.doc")
        case .commandTemplates:
            return .systemSymbol("terminal")
        }
    }

    var previewTint: Color {
        switch self {
        case .commonDirectories, .moveToCommonDirectory, .copyToCommonDirectory:
            return .blue
        case .createFile, .developerEntrypoints, .developerTools:
            return SettingsTheme.accent
        case .fileOperations:
            return .cyan
        case .commandTemplates:
            return SettingsTheme.accent
        }
    }
}

extension Set where Element == ActionVisibility {
    var displayName: String {
        sorted { $0.rawValue < $1.rawValue }
            .map(\.displayName)
            .joined(separator: " / ")
    }
}

extension ActionVisibility {
    var displayName: String {
        switch self {
        case .selection:
            return "选中文件"
        case .container:
            return "空白处"
        case .toolbar:
            return "工具栏"
        }
    }

    var systemImage: String {
        switch self {
        case .selection:
            return "checkmark.rectangle"
        case .container:
            return "rectangle.dashed"
        case .toolbar:
            return "sidebar.right"
        }
    }

    var helperText: String {
        switch self {
        case .selection:
            return "选中项目时显示"
        case .container:
            return "右键空白处时显示"
        case .toolbar:
            return "Finder 工具栏菜单中显示"
        }
    }
}

extension DeveloperTargetMode {
    static var allCasesForSettings: [DeveloperTargetMode] {
        [.dynamic, .currentDirectory, .selectedItem, .selectedItemDirectory]
    }

    var displayName: String {
        switch self {
        case .dynamic:
            return "动态"
        case .currentDirectory:
            return "当前目录"
        case .selectedItem:
            return "选中项目"
        case .selectedItemDirectory:
            return "选中项目所在目录"
        }
    }

    var helperText: String {
        switch self {
        case .dynamic:
            return "选中项目右键时传入选中项；空白处右键时传入当前 Finder 目录。"
        case .currentDirectory:
            return "始终把当前 Finder 目录传给目标应用。"
        case .selectedItem:
            return "优先把第一个选中项目传给目标应用，没有选中项时回退当前目录。"
        case .selectedItemDirectory:
            return "优先把第一个选中项目所在目录传给目标应用，没有选中项时回退当前目录。"
        }
    }
}
