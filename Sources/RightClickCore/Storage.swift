import Foundation

public struct RightClickStoragePaths: Equatable, Sendable {
    public var baseURL: URL
    public var configURL: URL
    public var bookmarksURL: URL
    public var cutClipboardURL: URL
    public var operationLogURL: URL

    public init(baseURL: URL) {
        self.baseURL = baseURL
        self.configURL = baseURL.appendingPathComponent("config.json")
        self.bookmarksURL = baseURL.appendingPathComponent("bookmarks.json")
        self.cutClipboardURL = baseURL.appendingPathComponent("cut-clipboard.json")
        self.operationLogURL = baseURL.appendingPathComponent("operation-log.jsonl")
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

public protocol RightClickConfigProviding {
    func loadConfig() throws -> RightClickConfig
    func loadBookmarkCatalog() throws -> DirectoryBookmarkCatalog
}

public struct FileBackedRightClickConfigProvider: RightClickConfigProviding {
    private let configStore: JSONFileStore<RightClickConfig>
    private let bookmarkStore: JSONFileStore<DirectoryBookmarkCatalog>

    public init(paths: RightClickStoragePaths) {
        self.configStore = JSONFileStore<RightClickConfig>(url: paths.configURL)
        self.bookmarkStore = JSONFileStore<DirectoryBookmarkCatalog>(url: paths.bookmarksURL)
    }

    public func loadConfig() throws -> RightClickConfig {
        try configStore.load(default: RightClickConfig())
    }

    public func loadBookmarkCatalog() throws -> DirectoryBookmarkCatalog {
        try bookmarkStore.load(default: DirectoryBookmarkCatalog())
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
