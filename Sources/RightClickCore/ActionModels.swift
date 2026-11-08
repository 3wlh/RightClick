import Foundation

public enum RightClickConstants {
    public static let currentSchemaVersion = 6
    public static let defaultAppGroupIdentifier = "group.com.local.rightclick"
    public static let defaultXPCServiceName = "com.local.rightclick.ActionRunner"
    public static let finderExtensionBundleIdentifier = "com.local.rightclick.FinderExtension"
    public static let defaultMaxRootMenuActions = 5
}

public enum ActionKind: String, Codable, CaseIterable, Equatable, Sendable {
    case openDirectory
    case moveToDirectory
    case copyToDirectory
    case cut
    case paste
    case createFile
    case openInApp
    case copyPath
    case hideItems
    case unhideItems
    case deletePermanently
    case undoOperation
}

public enum ActionVisibility: String, Codable, CaseIterable, Hashable, Sendable {
    case selection
    case container
    case toolbar
}

public enum ActionPlacement: String, Codable, Equatable, Sendable {
    case rootMenu
    case submenu
}

public enum MenuGroup: String, Codable, CaseIterable, Hashable, Sendable {
    case commonDirectories
    case moveToCommonDirectory
    case copyToCommonDirectory
    case createFile
    case developerEntrypoints
    case developerTools
    case fileOperations
}

public struct CustomMenuGroup: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var iconSymbol: String?

    public init(id: String, title: String, iconSymbol: String? = nil) {
        self.id = id
        self.title = title
        self.iconSymbol = iconSymbol
    }
}

public enum SubmenuGroupRef: Equatable, Hashable, Sendable {
    case builtIn(MenuGroup)
    case custom(String)

    public var rawValue: String {
        switch self {
        case .builtIn(let group):
            return group.rawValue
        case .custom(let id):
            return id
        }
    }
}

public struct ActionPayload: Codable, Equatable, Sendable {
    public var directoryID: String?
    public var templateID: String?
    public var developerEntrypointID: String?
    public var customGroupID: String?

    public init(
        directoryID: String? = nil,
        templateID: String? = nil,
        developerEntrypointID: String? = nil,
        customGroupID: String? = nil
    ) {
        self.directoryID = directoryID
        self.templateID = templateID
        self.developerEntrypointID = developerEntrypointID
        self.customGroupID = customGroupID
    }
}

public struct RightClickAction: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var kind: ActionKind
    public var visibility: Set<ActionVisibility>
    public var placement: ActionPlacement
    public var group: MenuGroup?
    public var isEnabled: Bool
    public var order: Int
    public var payload: ActionPayload

    public init(
        id: String,
        title: String,
        kind: ActionKind,
        visibility: Set<ActionVisibility>,
        placement: ActionPlacement,
        group: MenuGroup? = nil,
        isEnabled: Bool = true,
        order: Int,
        payload: ActionPayload = ActionPayload()
    ) {
        self.id = id
        self.title = title
        self.kind = kind
        self.visibility = visibility
        self.placement = placement
        self.group = group
        self.isEnabled = isEnabled
        self.order = order
        self.payload = payload
    }
}

public struct FileTemplate: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var defaultFileName: String
    public var contents: String

    public init(id: String, title: String, defaultFileName: String, contents: String = "") {
        self.id = id
        self.title = title
        self.defaultFileName = defaultFileName
        self.contents = contents
    }
}

public enum DeveloperTargetMode: String, Codable, Equatable, Sendable {
    case dynamic
    case currentDirectory
    case selectedItem
    case selectedItemDirectory
}

public struct DeveloperEntrypoint: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var bundleIdentifier: String
    public var targetMode: DeveloperTargetMode
    public var iconSymbol: String?
    /// 应用所在目录，bundleIdentifier 解析失败时用作兜底查找。
    public var applicationDirectory: String?

    public init(
        id: String,
        title: String,
        bundleIdentifier: String,
        targetMode: DeveloperTargetMode = .dynamic,
        iconSymbol: String? = nil,
        applicationDirectory: String? = nil
    ) {
        self.id = id
        self.title = title
        self.bundleIdentifier = bundleIdentifier
        self.targetMode = targetMode
        self.iconSymbol = iconSymbol
        self.applicationDirectory = applicationDirectory
    }
}

public struct RightClickConfig: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var maxRootMenuActions: Int
    public var shortcutDirectoryIDs: [String]
    public var actions: [RightClickAction]
    public var fileTemplates: [FileTemplate]
    public var developerEntrypoints: [DeveloperEntrypoint]
    public var customGroups: [CustomMenuGroup]
    public var submenuGroupOrder: [String]

    public init(
        schemaVersion: Int = RightClickConstants.currentSchemaVersion,
        maxRootMenuActions: Int = RightClickConstants.defaultMaxRootMenuActions,
        shortcutDirectoryIDs: [String] = [],
        actions: [RightClickAction] = RightClickConfig.defaultActions(),
        fileTemplates: [FileTemplate] = RightClickConfig.defaultFileTemplates(),
        developerEntrypoints: [DeveloperEntrypoint] = RightClickConfig.defaultDeveloperEntrypoints(),
        customGroups: [CustomMenuGroup] = [],
        submenuGroupOrder: [String] = MenuGroup.allCases.map(\.rawValue)
    ) {
        self.schemaVersion = schemaVersion
        self.maxRootMenuActions = maxRootMenuActions
        self.shortcutDirectoryIDs = shortcutDirectoryIDs
        self.actions = actions
        self.fileTemplates = fileTemplates
        self.developerEntrypoints = developerEntrypoints
        self.customGroups = customGroups
        self.submenuGroupOrder = submenuGroupOrder
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case maxRootMenuActions
        case shortcutDirectoryIDs
        case monitoredDirectoryIDs
        case commonDirectoryIDs
        case actions
        case fileTemplates
        case developerEntrypoints
        case customGroups
        case submenuGroupOrder
    }

    // 旧版本的命令模板动作（kind = runCommand）已移除，解码时逐项跳过，
    // 避免整个配置因为单个历史动作而无法加载。
    private struct LenientAction: Decodable {
        let action: RightClickAction?

        init(from decoder: Decoder) throws {
            action = try? RightClickAction(from: decoder)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? RightClickConstants.currentSchemaVersion
        self.maxRootMenuActions = try container.decodeIfPresent(Int.self, forKey: .maxRootMenuActions) ?? RightClickConstants.defaultMaxRootMenuActions
        self.shortcutDirectoryIDs = try container.decodeIfPresent([String].self, forKey: .shortcutDirectoryIDs)
            ?? container.decodeIfPresent([String].self, forKey: .commonDirectoryIDs)
            ?? []
        if let actions = try? container.decode([LenientAction].self, forKey: .actions) {
            self.actions = actions.compactMap(\.action)
        } else {
            self.actions = RightClickConfig.defaultActions()
        }
        self.fileTemplates = try container.decodeIfPresent([FileTemplate].self, forKey: .fileTemplates) ?? RightClickConfig.defaultFileTemplates()
        self.developerEntrypoints = try container.decodeIfPresent([DeveloperEntrypoint].self, forKey: .developerEntrypoints) ?? RightClickConfig.defaultDeveloperEntrypoints()
        self.customGroups = try container.decodeIfPresent([CustomMenuGroup].self, forKey: .customGroups) ?? []
        self.submenuGroupOrder = try container.decodeIfPresent([String].self, forKey: .submenuGroupOrder) ?? MenuGroup.allCases.map(\.rawValue)
        if self.schemaVersion < RightClickConstants.currentSchemaVersion {
            self.schemaVersion = RightClickConstants.currentSchemaVersion
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(RightClickConstants.currentSchemaVersion, forKey: .schemaVersion)
        try container.encode(maxRootMenuActions, forKey: .maxRootMenuActions)
        try container.encode(shortcutDirectoryIDs, forKey: .shortcutDirectoryIDs)
        try container.encode(actions, forKey: .actions)
        try container.encode(fileTemplates, forKey: .fileTemplates)
        try container.encode(developerEntrypoints, forKey: .developerEntrypoints)
        try container.encode(customGroups, forKey: .customGroups)
        try container.encode(resolvedSubmenuOrder.map(\.rawValue), forKey: .submenuGroupOrder)
    }

    /// Finder 右键菜单中各分组子菜单的实际展示顺序，包含内置分组与自定义分组。
    public var resolvedSubmenuOrder: [SubmenuGroupRef] {
        var refs: [SubmenuGroupRef] = []
        for rawValue in submenuGroupOrder {
            let ref: SubmenuGroupRef?
            if let group = MenuGroup(rawValue: rawValue) {
                ref = .builtIn(group)
            } else if customGroups.contains(where: { $0.id == rawValue }) {
                ref = .custom(rawValue)
            } else {
                ref = nil
            }
            guard let ref, !refs.contains(ref) else {
                continue
            }
            refs.append(ref)
        }
        for group in MenuGroup.allCases where !refs.contains(.builtIn(group)) {
            refs.append(.builtIn(group))
        }
        for group in customGroups where !refs.contains(.custom(group.id)) {
            refs.append(.custom(group.id))
        }
        return refs
    }

    /// 仅包含内置分组顺序，供需要 MenuGroup 列表的旧逻辑使用。
    public var resolvedSubmenuGroupOrder: [MenuGroup] {
        resolvedSubmenuOrder.compactMap { ref in
            guard case .builtIn(let group) = ref else {
                return nil
            }
            return group
        }
    }

    public static func defaultFileTemplates() -> [FileTemplate] {
        [
            FileTemplate(id: "template-txt", title: "空白文本", defaultFileName: "未命名.txt"),
            FileTemplate(id: "template-md", title: "Markdown", defaultFileName: "未命名.md", contents: "# Untitled\n"),
            FileTemplate(id: "template-json", title: "JSON", defaultFileName: "未命名.json", contents: "{\n  \n}\n")
        ]
    }

    public static func defaultDeveloperEntrypoints() -> [DeveloperEntrypoint] {
        [
            DeveloperEntrypoint(id: "developer-terminal", title: "在 Terminal 打开", bundleIdentifier: "com.apple.Terminal")
        ]
    }

    public static func defaultFileOperationActions(startingAt order: Int = 10) -> [RightClickAction] {
        [
            RightClickAction(
                id: "paste-here",
                title: "粘贴到此处",
                kind: .paste,
                visibility: [.container, .selection],
                placement: .rootMenu,
                group: .fileOperations,
                order: order
            ),
            RightClickAction(
                id: "cut-selection",
                title: "剪切",
                kind: .cut,
                visibility: [.selection],
                placement: .submenu,
                group: .fileOperations,
                order: order + 10
            ),
            RightClickAction(
                id: "copy-path",
                title: "拷贝路径",
                kind: .copyPath,
                visibility: [.selection, .container],
                placement: .submenu,
                group: .fileOperations,
                order: order + 20
            ),
            RightClickAction(
                id: "hide-selection",
                title: "隐藏文件",
                kind: .hideItems,
                visibility: [.selection],
                placement: .submenu,
                group: .fileOperations,
                order: order + 30
            ),
            RightClickAction(
                id: "unhide-selection",
                title: "取消隐藏",
                kind: .unhideItems,
                visibility: [.selection],
                placement: .submenu,
                group: .fileOperations,
                order: order + 40
            ),
            RightClickAction(
                id: "delete-permanently",
                title: "直接删除",
                kind: .deletePermanently,
                visibility: [.selection],
                placement: .submenu,
                group: .fileOperations,
                order: order + 50
            )
        ]
    }

    public static func defaultActions() -> [RightClickAction] {
        defaultFileOperationActions()
            + [
                RightClickAction(
                    id: "new-markdown",
                    title: "新建 Markdown 文件",
                    kind: .createFile,
                    visibility: [.container],
                    placement: .submenu,
                    group: .createFile,
                    order: 70,
                    payload: ActionPayload(templateID: "template-md")
                ),
                RightClickAction(
                    id: "open-terminal",
                    title: "在 Terminal 打开",
                    kind: .openInApp,
                    visibility: [.selection, .container, .toolbar],
                    placement: .submenu,
                    group: .developerEntrypoints,
                    order: 80,
                    payload: ActionPayload(developerEntrypointID: "developer-terminal")
                )
            ]
    }
}

public extension RightClickConstants {
    static let actionFailureNotificationName = "com.local.rightclick.action-failure"
    static let configurationChangedNotificationName = "com.local.rightclick.configuration-changed"
    static let actionFailureActionIDKey = "actionID"
    static let actionFailureActionKindKey = "actionKind"
    static let actionFailureMessageKey = "message"
    static let mainAppBundleIdentifier = "com.local.rightclick"
}
