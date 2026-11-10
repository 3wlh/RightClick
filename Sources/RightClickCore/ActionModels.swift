import Foundation

public enum RightClickConstants {
    public static let currentSchemaVersion = 8
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
    case airDrop
    case runCommand
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
    case commandTemplates
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
    public var commandTemplateID: String?

    public init(
        directoryID: String? = nil,
        templateID: String? = nil,
        developerEntrypointID: String? = nil,
        customGroupID: String? = nil,
        commandTemplateID: String? = nil
    ) {
        self.directoryID = directoryID
        self.templateID = templateID
        self.developerEntrypointID = developerEntrypointID
        self.customGroupID = customGroupID
        self.commandTemplateID = commandTemplateID
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

public enum CommandWorkingDirectory: String, Codable, CaseIterable, Sendable {
    case currentDirectory
    case selectedItemDirectory
}

public struct CommandTemplate: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var command: String
    public var workingDirectory: CommandWorkingDirectory
    /// 额外环境变量，一行一个 KEY=value，支持 # 注释。
    public var environment: String
    /// 超时秒数。
    public var timeoutSeconds: Int
    /// 是否在系统终端中运行；关闭时后台静默执行，不显示输出。
    public var runInTerminal: Bool
    public var iconSymbol: String?

    public init(
        id: String,
        title: String,
        command: String,
        workingDirectory: CommandWorkingDirectory = .currentDirectory,
        environment: String = "",
        timeoutSeconds: Int = 60,
        runInTerminal: Bool = true,
        iconSymbol: String? = nil
    ) {
        self.id = id
        self.title = title
        self.command = command
        self.workingDirectory = workingDirectory
        self.environment = environment
        self.timeoutSeconds = timeoutSeconds
        self.runInTerminal = runInTerminal
        self.iconSymbol = iconSymbol
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case command
        case workingDirectory
        case environment
        case timeoutSeconds
        case runInTerminal
        case iconSymbol
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)
        self.command = try container.decode(String.self, forKey: .command)
        self.workingDirectory = try container.decodeIfPresent(CommandWorkingDirectory.self, forKey: .workingDirectory) ?? .currentDirectory
        self.environment = try container.decodeIfPresent(String.self, forKey: .environment) ?? ""
        self.timeoutSeconds = try container.decodeIfPresent(Int.self, forKey: .timeoutSeconds) ?? 60
        self.runInTerminal = try container.decodeIfPresent(Bool.self, forKey: .runInTerminal) ?? true
        self.iconSymbol = try container.decodeIfPresent(String.self, forKey: .iconSymbol)
    }
}

/// 解析命令模板中的环境变量文本。
public enum CommandEnvironment {
    /// 每行一个 `KEY=value`，忽略空行与 `#` 注释，兼容 Pro 的 `KEY!=value` 写法（按普通变量处理）。
    public static func parse(_ text: String) -> [String: String] {
        var result: [String: String] = [:]

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), let separator = line.firstIndex(of: "=") else {
                continue
            }

            var key = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
            var value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)

            if key.hasSuffix("!") {
                key = String(key.dropLast()).trimmingCharacters(in: .whitespaces)
            }
            guard !key.isEmpty, isValidIdentifier(key) else {
                continue
            }

            if value.count >= 2,
               (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            result[key] = value
        }
        return result
    }

    private static func isValidIdentifier(_ key: String) -> Bool {
        guard let first = key.first, first.isLetter || first == "_" else {
            return false
        }
        return key.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }
}

/// 命令模板占位符：`{{currentDirectory}}`、`{{selectedPath}}`、`{{selectedPaths}}`，兼容旧写法 `%s`。
public enum CommandPlaceholder {
    public static let currentDirectoryToken = "{{currentDirectory}}"
    public static let selectedPathToken = "{{selectedPath}}"
    public static let selectedPathsToken = "{{selectedPaths}}"
    /// 兼容旧写法：按选中顺序逐个替换。
    public static let positionalToken = "%s"

    /// 按占位符替换命令中的路径，所有路径都会自动加 shell 引号。
    /// - `{{currentDirectory}}`：工作目录
    /// - `{{selectedPath}}`：第一个选中项
    /// - `{{selectedPaths}}`：全部选中项，空格分隔
    /// - `%s`：按顺序依次对应一个选中项
    /// 未选中任何项目时，选中类占位符回退为工作目录。
    public static func expand(_ command: String, selectedItems: [URL], fallbackDirectory: URL? = nil) -> String {
        let quotedItems = selectedItems.map { shellQuoted($0.path) }
        let fallbackValue = fallbackDirectory.map { shellQuoted($0.path) } ?? ""
        let selectedPathsValue = quotedItems.isEmpty ? fallbackValue : quotedItems.joined(separator: " ")
        let selectedPathValue = quotedItems.first ?? fallbackValue

        var result = ""
        var index = command.startIndex
        var positionalIndex = 0

        while index < command.endIndex {
            let rest = command[index...]
            if rest.hasPrefix(currentDirectoryToken) {
                result += fallbackValue
                index = command.index(index, offsetBy: currentDirectoryToken.count)
            } else if rest.hasPrefix(selectedPathsToken) {
                result += selectedPathsValue
                index = command.index(index, offsetBy: selectedPathsToken.count)
            } else if rest.hasPrefix(selectedPathToken) {
                result += selectedPathValue
                index = command.index(index, offsetBy: selectedPathToken.count)
            } else if rest.hasPrefix(positionalToken) {
                if selectedItems.isEmpty {
                    result += fallbackValue
                } else if positionalIndex < quotedItems.count {
                    result += quotedItems[positionalIndex]
                }
                positionalIndex += 1
                index = command.index(index, offsetBy: positionalToken.count)
            } else {
                result.append(command[index])
                index = command.index(after: index)
            }
        }
        return result
    }

    private static func shellQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// Finder 扩展转发给主 App 的命令执行请求。
public struct CommandRunRequest: Codable, Equatable, Sendable {
    public var actionID: String
    public var context: FinderContext

    public init(actionID: String, context: FinderContext) {
        self.actionID = actionID
        self.context = context
    }
}

/// 命令请求的 URL 通道。
/// 沙盒进程无法通过 DistributedNotificationCenter 携带 userInfo，
/// 因此改用 rightclick://run-command?request=<base64url> 唤起主 App。
public enum CommandRunURL {
    public static let scheme = "rightclick"
    public static let host = "run-command"
    public static let requestQueryItemName = "request"

    public static func url(for request: CommandRunRequest) -> URL? {
        guard let data = try? JSONEncoder().encode(request) else {
            return nil
        }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.queryItems = [
            URLQueryItem(name: requestQueryItemName, value: base64URLEncoded(data))
        ]
        return components.url
    }

    public static func request(from url: URL) -> CommandRunRequest? {
        guard
            url.scheme == scheme,
            url.host == host,
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let value = components.queryItems?.first(where: { $0.name == requestQueryItemName })?.value,
            let data = data(fromBase64URL: value)
        else {
            return nil
        }
        return try? JSONDecoder().decode(CommandRunRequest.self, from: data)
    }

    private static func base64URLEncoded(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func data(fromBase64URL value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: base64)
    }
}

/// AirDrop 分享请求：由 Finder 扩展通过 URL Scheme 转发给主 App 展示分享面板。
public struct AirDropShareRequest: Codable, Equatable, Sendable {
    public var paths: [String]

    public init(paths: [String]) {
        self.paths = paths
    }
}

public enum AirDropShareURL {
    public static let scheme = "rightclick"
    public static let host = "airdrop"
    public static let requestQueryItemName = "request"

    public static func url(for request: AirDropShareRequest) -> URL? {
        guard let data = try? JSONEncoder().encode(request) else {
            return nil
        }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.queryItems = [
            URLQueryItem(name: requestQueryItemName, value: base64URLEncoded(data))
        ]
        return components.url
    }

    public static func request(from url: URL) -> AirDropShareRequest? {
        guard
            url.scheme == scheme,
            url.host == host,
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            let value = components.queryItems?.first(where: { $0.name == requestQueryItemName })?.value,
            let data = data(fromBase64URL: value)
        else {
            return nil
        }
        return try? JSONDecoder().decode(AirDropShareRequest.self, from: data)
    }

    private static func base64URLEncoded(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func data(fromBase64URL value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: base64)
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
    public var commandTemplates: [CommandTemplate]
    public var developerEntrypoints: [DeveloperEntrypoint]
    public var customGroups: [CustomMenuGroup]
    public var submenuGroupOrder: [String]

    public init(
        schemaVersion: Int = RightClickConstants.currentSchemaVersion,
        maxRootMenuActions: Int = RightClickConstants.defaultMaxRootMenuActions,
        shortcutDirectoryIDs: [String] = [],
        actions: [RightClickAction] = RightClickConfig.defaultActions(),
        fileTemplates: [FileTemplate] = RightClickConfig.defaultFileTemplates(),
        commandTemplates: [CommandTemplate] = RightClickConfig.defaultCommandTemplates(),
        developerEntrypoints: [DeveloperEntrypoint] = RightClickConfig.defaultDeveloperEntrypoints(),
        customGroups: [CustomMenuGroup] = [],
        submenuGroupOrder: [String] = MenuGroup.allCases.map(\.rawValue)
    ) {
        self.schemaVersion = schemaVersion
        self.maxRootMenuActions = maxRootMenuActions
        self.shortcutDirectoryIDs = shortcutDirectoryIDs
        self.actions = actions
        self.fileTemplates = fileTemplates
        self.commandTemplates = commandTemplates
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
        case commandTemplates
        case developerEntrypoints
        case customGroups
        case submenuGroupOrder
    }

    // 历史动作逐项解码，避免整个配置因为单个无法识别的动作而无法加载。
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
        self.commandTemplates = try container.decodeIfPresent([CommandTemplate].self, forKey: .commandTemplates) ?? []
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
        try container.encode(commandTemplates, forKey: .commandTemplates)
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
                id: "copy-path",
                title: "拷贝路径",
                kind: .copyPath,
                visibility: [.selection, .container],
                placement: .submenu,
                group: .fileOperations,
                order: order
            ),
            RightClickAction(
                id: "paste-here",
                title: "粘贴到此处",
                kind: .paste,
                visibility: [.container, .selection],
                placement: .submenu,
                group: .fileOperations,
                order: order + 10
            ),
            RightClickAction(
                id: "cut-selection",
                title: "剪切",
                kind: .cut,
                visibility: [.selection],
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
            ),
            RightClickAction(
                id: "airdrop-share",
                title: "AirDrop 发送",
                kind: .airDrop,
                visibility: [.selection],
                placement: .submenu,
                group: .fileOperations,
                isEnabled: false,
                order: order + 60
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
                ),
                RightClickAction(
                    id: "run-command-clear-quarantine",
                    title: "清除隔离属性",
                    kind: .runCommand,
                    visibility: [.selection, .container],
                    placement: .submenu,
                    group: .commandTemplates,
                    isEnabled: false,
                    order: 90,
                    payload: ActionPayload(commandTemplateID: "command-clear-quarantine")
                )
            ]
    }

    /// 随应用一同安装的默认命令模板，对应菜单项默认关闭，需要在设置中手动启用。
    public static func defaultCommandTemplates() -> [CommandTemplate] {
        [
            CommandTemplate(
                id: "command-clear-quarantine",
                title: "清除隔离属性",
                command: "xattr -dr com.apple.quarantine {{selectedPaths}}",
                workingDirectory: .currentDirectory,
                timeoutSeconds: 60,
                runInTerminal: true,
                iconSymbol: "terminal"
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
