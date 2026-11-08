import Foundation

public struct RightClickStoragePaths: Equatable, Sendable {
    public var baseURL: URL
    public var configURL: URL
    /// 旧版配置文件路径，仅用于迁移。
    public var legacyConfigURL: URL
    public var bookmarksURL: URL

    public init(baseURL: URL) {
        self.baseURL = baseURL
        self.configURL = baseURL.appendingPathComponent("rightclick.json")
        self.legacyConfigURL = baseURL.appendingPathComponent("config.json")
        self.bookmarksURL = baseURL.appendingPathComponent("bookmarks.json")
    }

    public static func appGroup(identifier: String = RightClickConstants.defaultAppGroupIdentifier) throws -> RightClickStoragePaths {
        guard let baseURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) else {
            throw StorageError.appGroupContainerUnavailable(identifier)
        }
        return RightClickStoragePaths(baseURL: baseURL)
    }

    public static func applicationSupport(
        fileManager: FileManager = .default,
        bundleIdentifier: String = RightClickConstants.mainAppBundleIdentifier,
        realUserHomeDirectory: URL? = nil
    ) -> RightClickStoragePaths {
        let homeDirectory = UserHomeDirectoryResolver.realUserHomeDirectory(
            processHomeDirectory: fileManager.homeDirectoryForCurrentUser,
            override: realUserHomeDirectory
        )
        let baseURL = homeDirectory
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent(bundleIdentifier)
        return RightClickStoragePaths(baseURL: baseURL)
    }

    public static func defaultForCurrentProcess(
        appGroupIdentifier: String = RightClickConstants.defaultAppGroupIdentifier,
        fileManager: FileManager = .default,
        realUserHomeDirectory: URL? = nil
    ) -> RightClickStoragePaths {
        _ = appGroupIdentifier
        return applicationSupport(fileManager: fileManager, realUserHomeDirectory: realUserHomeDirectory)
    }
}

public enum StorageError: Error, Equatable, Sendable {
    case appGroupContainerUnavailable(String)
    case missingRequiredFile(URL)
}

public final class JSONFileStore<Value: Codable> {
    public let url: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(url: URL, fileManager: FileManager = .default) {
        self.url = url
        self.fileManager = fileManager
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
    }

    public func load(default defaultValue: @autoclosure () -> Value) throws -> Value {
        guard fileManager.fileExists(atPath: url.path) else {
            return defaultValue()
        }
        let data = try Data(contentsOf: url)
        return try decoder.decode(Value.self, from: data)
    }

    public func loadRequired() throws -> Value {
        guard fileManager.fileExists(atPath: url.path) else {
            throw StorageError.missingRequiredFile(url)
        }
        let data = try Data(contentsOf: url)
        return try decoder.decode(Value.self, from: data)
    }

    public func save(_ value: Value) throws {
        let directory = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try encoder.encode(value)
        try data.write(to: url, options: [.atomic])
    }
}

public struct PersistedConfiguration: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var config: RightClickConfig
    public var bookmarks: DirectoryBookmarkCatalog

    public init(
        config: RightClickConfig,
        bookmarks: DirectoryBookmarkCatalog,
        schemaVersion: Int = PersistedConfiguration.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.config = config
        self.bookmarks = bookmarks
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case config
        case bookmarks
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.currentSchemaVersion
        config = try container.decode(RightClickConfig.self, forKey: .config)
        bookmarks = try container.decodeIfPresent(DirectoryBookmarkCatalog.self, forKey: .bookmarks)
            ?? DirectoryBookmarkCatalog()
    }
}

/// 统一 rightclick.json 的读写，并兼容旧版「config.json + bookmarks.json」分离格式。
public enum PersistedConfigurationStore {
    public static func load(
        paths: RightClickStoragePaths,
        fileManager: FileManager = .default
    ) throws -> (document: PersistedConfiguration, isLegacy: Bool)? {
        let existingURL = [paths.configURL, paths.legacyConfigURL]
            .first { fileManager.fileExists(atPath: $0.path) }
        guard let sourceURL = existingURL else {
            return nil
        }
        let isLegacyFile = sourceURL != paths.configURL

        if let document = try? JSONFileStore<PersistedConfiguration>(url: sourceURL, fileManager: fileManager).loadRequired() {
            return (document, isLegacyFile)
        }

        // 旧版 config.json 顶层直接是 RightClickConfig，书签单独存放在 bookmarks.json。
        let legacyConfig = try JSONFileStore<RightClickConfig>(url: sourceURL, fileManager: fileManager).loadRequired()
        let legacyBookmarks = try JSONFileStore<DirectoryBookmarkCatalog>(url: paths.bookmarksURL, fileManager: fileManager)
            .load(default: DirectoryBookmarkCatalog())
        return (PersistedConfiguration(config: legacyConfig, bookmarks: legacyBookmarks), true)
    }

    public static func save(
        _ document: PersistedConfiguration,
        paths: RightClickStoragePaths,
        fileManager: FileManager = .default
    ) throws {
        try JSONFileStore<PersistedConfiguration>(url: paths.configURL, fileManager: fileManager).save(document)

        // 迁移完成后清理旧版遗留文件，避免出现多份数据。
        for url in [paths.legacyConfigURL, paths.bookmarksURL] where fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }
    }
}

public protocol RightClickConfigProviding {
    func loadConfig() throws -> RightClickConfig
    func loadBookmarkCatalog() throws -> DirectoryBookmarkCatalog
}

public struct FileBackedRightClickConfigProvider: RightClickConfigProviding {
    private let paths: RightClickStoragePaths
    private let fileManager: FileManager

    public init(paths: RightClickStoragePaths, fileManager: FileManager = .default) {
        self.paths = paths
        self.fileManager = fileManager
    }

    public func loadConfig() throws -> RightClickConfig {
        try loadDocument().config
    }

    public func loadBookmarkCatalog() throws -> DirectoryBookmarkCatalog {
        try loadDocument().bookmarks
    }

    private func loadDocument() throws -> PersistedConfiguration {
        if let loaded = try PersistedConfigurationStore.load(paths: paths, fileManager: fileManager) {
            return loaded.document
        }
        return PersistedConfiguration(config: RightClickConfig(), bookmarks: DirectoryBookmarkCatalog())
    }
}

public struct StaticRightClickConfigProvider: RightClickConfigProviding {
    public var config: RightClickConfig
    public var bookmarkCatalog: DirectoryBookmarkCatalog

    public init(config: RightClickConfig, bookmarkCatalog: DirectoryBookmarkCatalog = DirectoryBookmarkCatalog()) {
        self.config = config
        self.bookmarkCatalog = bookmarkCatalog
    }

    public func loadConfig() throws -> RightClickConfig {
        config
    }

    public func loadBookmarkCatalog() throws -> DirectoryBookmarkCatalog {
        bookmarkCatalog
    }
}
