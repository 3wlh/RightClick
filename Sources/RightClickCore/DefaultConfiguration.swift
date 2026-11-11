import Foundation

/// 安装时使用的默认配置。
///
/// 默认值以 JSON 文本形式内嵌在 `BundledDefaultConfiguration.swift` 中，随代码编译进二进制。
/// 解析失败时退回 `fallback` 的硬编码默认值，保证应用始终能启动。
public struct DefaultConfiguration: Equatable, Sendable {
    /// 默认常用目录。`path` 支持 `~` 前缀，运行时展开为真实用户目录；路径不存在时跳过。
    public struct Directory: Codable, Equatable, Sendable {
        public var id: String
        public var title: String
        public var path: String
        /// 该目录的三个菜单动作（前往 / 移动到 / 复制到）是否默认启用，省略时为 false。
        public var isEnabled: Bool?

        public init(id: String, title: String, path: String, isEnabled: Bool? = nil) {
            self.id = id
            self.title = title
            self.path = path
            self.isEnabled = isEnabled
        }
    }

    /// 默认动作描述。省略的字段使用默认值：`placement` 为子菜单、`isEnabled` 为 true。
    public struct Action: Codable, Equatable, Sendable {
        public var id: String
        public var title: String
        public var kind: ActionKind
        public var visibility: [ActionVisibility]
        public var placement: ActionPlacement?
        public var group: MenuGroup?
        public var isEnabled: Bool?
        public var payload: ActionPayload?

        public init(
            id: String,
            title: String,
            kind: ActionKind,
            visibility: [ActionVisibility],
            placement: ActionPlacement? = nil,
            group: MenuGroup? = nil,
            isEnabled: Bool? = nil,
            payload: ActionPayload? = nil
        ) {
            self.id = id
            self.title = title
            self.kind = kind
            self.visibility = visibility
            self.placement = placement
            self.group = group
            self.isEnabled = isEnabled
            self.payload = payload
        }

        func makeAction(order: Int, defaultGroup: MenuGroup) -> RightClickAction {
            RightClickAction(
                id: id,
                title: title,
                kind: kind,
                visibility: Set(visibility),
                placement: placement ?? .submenu,
                group: group ?? defaultGroup,
                isEnabled: isEnabled ?? true,
                order: order,
                payload: payload ?? ActionPayload()
            )
        }
    }

    /// 默认文件模板。`contents` 可省略，默认为空文件；
    /// `isEnabled` 控制「新建 xxx」菜单项是否默认启用，省略时为 true。
    public struct Template: Codable, Equatable, Sendable {
        public var id: String
        public var title: String
        public var defaultFileName: String
        public var contents: String?
        public var isEnabled: Bool?

        public init(
            id: String,
            title: String,
            defaultFileName: String,
            contents: String? = nil,
            isEnabled: Bool? = nil
        ) {
            self.id = id
            self.title = title
            self.defaultFileName = defaultFileName
            self.contents = contents
            self.isEnabled = isEnabled
        }

        var fileTemplate: FileTemplate {
            FileTemplate(
                id: id,
                title: title,
                defaultFileName: defaultFileName,
                contents: contents ?? ""
            )
        }
    }

    /// 默认应用入口。`targetMode` 可省略，默认为 dynamic；
    /// `isEnabled` 控制「在 xxx 打开」菜单项是否默认启用，省略时为 true。
    public struct Entrypoint: Codable, Equatable, Sendable {
        public var id: String
        public var title: String
        public var bundleIdentifier: String
        public var targetMode: DeveloperTargetMode?
        public var iconSymbol: String?
        public var applicationDirectory: String?
        public var applicationPath: String?
        public var isEnabled: Bool?

        public init(
            id: String,
            title: String,
            bundleIdentifier: String,
            targetMode: DeveloperTargetMode? = nil,
            iconSymbol: String? = nil,
            applicationDirectory: String? = nil,
            applicationPath: String? = nil,
            isEnabled: Bool? = nil
        ) {
            self.id = id
            self.title = title
            self.bundleIdentifier = bundleIdentifier
            self.targetMode = targetMode
            self.iconSymbol = iconSymbol
            self.applicationDirectory = applicationDirectory
            self.applicationPath = applicationPath
            self.isEnabled = isEnabled
        }

        var developerEntrypoint: DeveloperEntrypoint {
            DeveloperEntrypoint(
                id: id,
                title: title,
                bundleIdentifier: bundleIdentifier,
                targetMode: targetMode ?? .dynamic,
                iconSymbol: iconSymbol,
                applicationDirectory: applicationDirectory,
                applicationPath: applicationPath
            )
        }
    }

    /// 默认命令模板。省略的字段使用与 `CommandTemplate` 相同的默认值；
    /// `isEnabled` 控制生成的命令菜单项是否默认启用，省略时为 false。
    public struct Command: Codable, Equatable, Sendable {
        public var id: String
        public var title: String
        public var command: String
        public var workingDirectory: CommandWorkingDirectory?
        public var environment: String?
        public var timeoutSeconds: Int?
        public var runInTerminal: Bool?
        public var iconSymbol: String?
        public var isEnabled: Bool?

        public init(
            id: String,
            title: String,
            command: String,
            workingDirectory: CommandWorkingDirectory? = nil,
            environment: String? = nil,
            timeoutSeconds: Int? = nil,
            runInTerminal: Bool? = nil,
            iconSymbol: String? = nil,
            isEnabled: Bool? = nil
        ) {
            self.id = id
            self.title = title
            self.command = command
            self.workingDirectory = workingDirectory
            self.environment = environment
            self.timeoutSeconds = timeoutSeconds
            self.runInTerminal = runInTerminal
            self.iconSymbol = iconSymbol
            self.isEnabled = isEnabled
        }

        var commandTemplate: CommandTemplate {
            CommandTemplate(
                id: id,
                title: title,
                command: command,
                workingDirectory: workingDirectory ?? .currentDirectory,
                environment: environment ?? "",
                timeoutSeconds: timeoutSeconds ?? 60,
                runInTerminal: runInTerminal ?? true,
                iconSymbol: iconSymbol
            )
        }
    }

    public var maxRootMenuActions: Int
    public var submenuGroupOrder: [String]
    public var directories: [Directory]
    public var fileOperationActions: [Action]
    public var fileTemplates: [Template]
    public var developerEntrypoints: [Entrypoint]
    public var commandTemplates: [Command]

    public init(
        maxRootMenuActions: Int = RightClickConstants.defaultMaxRootMenuActions,
        submenuGroupOrder: [String] = MenuGroup.allCases.map(\.rawValue),
        directories: [Directory] = [],
        fileOperationActions: [Action] = [],
        fileTemplates: [Template] = [],
        developerEntrypoints: [Entrypoint] = [],
        commandTemplates: [Command] = []
    ) {
        self.maxRootMenuActions = maxRootMenuActions
        self.submenuGroupOrder = submenuGroupOrder
        self.directories = directories
        self.fileOperationActions = fileOperationActions
        self.fileTemplates = fileTemplates
        self.developerEntrypoints = developerEntrypoints
        self.commandTemplates = commandTemplates
    }

    public var resolvedFileTemplates: [FileTemplate] {
        fileTemplates.map(\.fileTemplate)
    }

    public var resolvedDeveloperEntrypoints: [DeveloperEntrypoint] {
        developerEntrypoints.map(\.developerEntrypoint)
    }

    public var resolvedCommandTemplates: [CommandTemplate] {
        commandTemplates.map(\.commandTemplate)
    }
}

public extension DefaultConfiguration {
    /// 与历史上硬编码默认值完全一致的内置兜底配置。
    static let fallback: DefaultConfiguration = {
        let fileOperations = RightClickConfig.defaultFileOperationActions(startingAt: 0).map { action in
            Action(
                id: action.id,
                title: action.title,
                kind: action.kind,
                visibility: ActionVisibility.allCases.filter { action.visibility.contains($0) },
                placement: action.placement,
                group: action.group,
                isEnabled: action.isEnabled,
                payload: action.payload
            )
        }

        return DefaultConfiguration(
            maxRootMenuActions: RightClickConstants.defaultMaxRootMenuActions,
            submenuGroupOrder: MenuGroup.allCases.map(\.rawValue),
            directories: [
                Directory(id: "desktop", title: "桌面", path: "~/Desktop"),
                Directory(id: "downloads", title: "下载", path: "~/Downloads")
            ],
            fileOperationActions: fileOperations,
            fileTemplates: RightClickConfig.defaultFileTemplates().map {
                Template(
                    id: $0.id,
                    title: $0.title,
                    defaultFileName: $0.defaultFileName,
                    contents: $0.contents,
                    isEnabled: true
                )
            },
            developerEntrypoints: RightClickConfig.defaultDeveloperEntrypoints().map {
                Entrypoint(
                    id: $0.id,
                    title: $0.title,
                    bundleIdentifier: $0.bundleIdentifier,
                    targetMode: $0.targetMode,
                    iconSymbol: $0.iconSymbol,
                    applicationDirectory: $0.applicationDirectory,
                    applicationPath: $0.applicationPath,
                    isEnabled: true
                )
            },
            commandTemplates: RightClickConfig.defaultCommandTemplates().map {
                Command(
                    id: $0.id,
                    title: $0.title,
                    command: $0.command,
                    workingDirectory: $0.workingDirectory,
                    environment: $0.environment,
                    timeoutSeconds: $0.timeoutSeconds,
                    runInTerminal: $0.runInTerminal,
                    iconSymbol: $0.iconSymbol,
                    isEnabled: false
                )
            }
        )
    }()
}

extension DefaultConfiguration: Decodable {
    enum CodingKeys: String, CodingKey {
        case maxRootMenuActions
        case submenuGroupOrder
        case directories
        case fileOperationActions
        case fileTemplates
        case developerEntrypoints
        case commandTemplates
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = DefaultConfiguration.fallback

        maxRootMenuActions = try container.decodeIfPresent(Int.self, forKey: .maxRootMenuActions)
            ?? fallback.maxRootMenuActions
        submenuGroupOrder = try container.decodeIfPresent([String].self, forKey: .submenuGroupOrder)
            ?? fallback.submenuGroupOrder
        directories = try container.decodeIfPresent([Directory].self, forKey: .directories)
            ?? fallback.directories
        fileOperationActions = try container.decodeIfPresent([Action].self, forKey: .fileOperationActions)
            ?? fallback.fileOperationActions
        fileTemplates = try container.decodeIfPresent([Template].self, forKey: .fileTemplates)
            ?? fallback.fileTemplates
        developerEntrypoints = try container.decodeIfPresent([Entrypoint].self, forKey: .developerEntrypoints)
            ?? fallback.developerEntrypoints
        commandTemplates = try container.decodeIfPresent([Command].self, forKey: .commandTemplates)
            ?? fallback.commandTemplates
    }
}
