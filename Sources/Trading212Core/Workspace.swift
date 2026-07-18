import Darwin
import Foundation

/// Variant-isolated, non-secret on-disk state shared by the app and CLI.
public struct Workspace: Equatable, Sendable {
    public let rootURL: URL

    public init(rootURL: URL) {
        self.rootURL = rootURL.standardizedFileURL
    }

    public init(variant: AppVariant = .current, fileManager: FileManager = .default) throws {
        guard let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw WorkspaceError.applicationSupportUnavailable
        }
        self.init(rootURL: applicationSupport.appending(
            component: variant.workspaceDirectoryName, directoryHint: .isDirectory))
    }

    public var settingsURL: URL { rootURL.appending(component: "settings.json") }
    public var accountMetadataURL: URL { rootURL.appending(component: "account.json") }
    public var cacheDirectoryURL: URL {
        rootURL.appending(component: "cache", directoryHint: .isDirectory)
    }
    public var accountSnapshotURL: URL {
        cacheDirectoryURL.appending(component: "account-snapshot.json")
    }
    public func accountSnapshotURL(for environment: Trading212Environment) -> URL {
        cacheDirectoryURL.appending(component: "account-snapshot-\(environment.rawValue).json")
    }
    public var snapshotsDirectoryURL: URL {
        rootURL.appending(component: "snapshots", directoryHint: .isDirectory)
    }
    public var receiptsDirectoryURL: URL {
        rootURL.appending(component: "receipts", directoryHint: .isDirectory)
    }
    public var auditLogURL: URL { rootURL.appending(component: "audit.jsonl") }

    public func prepare(using fileSystem: any FileSystem = LocalFileSystem()) throws {
        try fileSystem.createDirectory(at: rootURL, permissions: .ownerOnlyDirectory)
        try fileSystem.createDirectory(at: cacheDirectoryURL, permissions: .ownerOnlyDirectory)
        try fileSystem.createDirectory(at: snapshotsDirectoryURL, permissions: .ownerOnlyDirectory)
        try fileSystem.createDirectory(at: receiptsDirectoryURL, permissions: .ownerOnlyDirectory)
    }
}

public enum WorkspaceError: Error, Equatable, Sendable {
    case applicationSupportUnavailable
}

public struct FilePermissions: RawRepresentable, Codable, Equatable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    public static let ownerReadWrite = FilePermissions(rawValue: 0o600)
    public static let ownerOnlyDirectory = FilePermissions(rawValue: 0o700)
}

public protocol FileSystem: Sendable {
    func data(at url: URL) throws -> Data
    func fileExists(at url: URL) -> Bool
    func createDirectory(at url: URL, permissions: FilePermissions) throws
    func removeItem(at url: URL) throws

    /// Returns the backup URL when an existing destination was backed up.
    @discardableResult
    func writeAtomically(_ data: Data, to url: URL,
                         permissions: FilePermissions,
                         backupExisting: Bool) throws -> URL?
}

public struct LocalFileSystem: FileSystem, Sendable {
    public init() {}

    public func data(at url: URL) throws -> Data { try Data(contentsOf: url) }
    public func fileExists(at url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }

    public func createDirectory(at url: URL, permissions: FilePermissions) throws {
        let existed = FileManager.default.fileExists(atPath: url.path)
        try FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: true,
            attributes: [.posixPermissions: permissions.rawValue])
        try FileManager.default.setAttributes(
            [.posixPermissions: permissions.rawValue], ofItemAtPath: url.path)
        if !existed {
            try syncDirectory(at: url)
            try syncDirectory(at: url.deletingLastPathComponent())
        }
    }

    public func removeItem(at url: URL) throws {
        do { try FileManager.default.removeItem(at: url) }
        catch let error as CocoaError where error.code == .fileNoSuchFile { return }
    }

    @discardableResult
    public func writeAtomically(_ data: Data, to url: URL,
                                permissions: FilePermissions = .ownerReadWrite,
                                backupExisting: Bool = false) throws -> URL? {
        let manager = FileManager.default
        let parent = url.deletingLastPathComponent()
        // Never chmod an existing user-selected parent (for example when the
        // CLI writes `./portfolio.json`). Only directories we create are 0700.
        if !manager.fileExists(atPath: parent.path) {
            try createDirectory(at: parent, permissions: .ownerOnlyDirectory)
        }

        var backupURL: URL?
        if backupExisting, manager.fileExists(atPath: url.path) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            let candidate = URL(fileURLWithPath: url.path + ".\(formatter.string(from: Date())).bak")
            var unique = candidate
            var suffix = 1
            while manager.fileExists(atPath: unique.path) {
                unique = URL(fileURLWithPath: candidate.path + ".\(suffix)")
                suffix += 1
            }
            try createDurableFile(
                manager.contents(atPath: url.path) ?? Data(contentsOf: url),
                at: unique,
                permissions: permissions
            )
            try syncDirectory(at: parent)
            backupURL = unique
        }

        let temporary = parent.appending(
            component: ".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        do {
            // O_EXCL plus an explicit mode prevents even a transient 0644
            // secret/portfolio file in a user-selected shared directory.
            try createDurableFile(data, at: temporary, permissions: permissions)
            guard Darwin.rename(temporary.path, url.path) == 0 else {
                throw posixError(path: url.path)
            }
            // The rename is not considered committed until the containing
            // directory is synced. Trading code relies on this before POSTing.
            try syncDirectory(at: parent)
        } catch {
            try? manager.removeItem(at: temporary)
            throw error
        }
        return backupURL
    }

    private func createDurableFile(
        _ data: Data,
        at url: URL,
        permissions: FilePermissions
    ) throws {
        let descriptor = Darwin.open(
            url.path,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
            mode_t(permissions.rawValue)
        )
        guard descriptor >= 0 else { throw posixError(path: url.path) }

        var operationError: Error?
        if Darwin.fchmod(descriptor, mode_t(permissions.rawValue)) != 0 {
            operationError = posixError(path: url.path)
        } else if !writeAll(data, to: descriptor) {
            operationError = posixError(path: url.path)
        } else if Darwin.fsync(descriptor) != 0 {
            operationError = posixError(path: url.path)
        }
        if Darwin.close(descriptor) != 0, operationError == nil {
            operationError = posixError(path: url.path)
        }
        if let operationError {
            try? FileManager.default.removeItem(at: url)
            throw operationError
        }
    }

    private func writeAll(_ data: Data, to descriptor: Int32) -> Bool {
        data.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return data.isEmpty }
            var offset = 0
            while offset < bytes.count {
                let written = Darwin.write(
                    descriptor,
                    base.advanced(by: offset),
                    bytes.count - offset
                )
                if written > 0 {
                    offset += written
                } else if written < 0, errno == EINTR {
                    continue
                } else {
                    return false
                }
            }
            return true
        }
    }

    private func syncDirectory(at url: URL) throws {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard descriptor >= 0 else { throw posixError(path: url.path) }
        let result = Darwin.fsync(descriptor)
        let savedErrno = errno
        _ = Darwin.close(descriptor)
        guard result == 0 else {
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(savedErrno),
                userInfo: [NSFilePathErrorKey: url.path]
            )
        }
    }

    private func posixError(path: String) -> NSError {
        NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(errno),
            userInfo: [NSFilePathErrorKey: path]
        )
    }
}

public enum AtomicJSONFile {
    public static func read<Value: Decodable>(
        _ type: Value.Type, from url: URL,
        fileSystem: any FileSystem = LocalFileSystem()) throws -> Value {
        try StorageJSON.decoder().decode(type, from: fileSystem.data(at: url))
    }

    @discardableResult
    public static func write<Value: Encodable>(
        _ value: Value, to url: URL,
        fileSystem: any FileSystem = LocalFileSystem(),
        permissions: FilePermissions = .ownerReadWrite,
        backupExisting: Bool = false) throws -> URL? {
        let data = try StorageJSON.encoder().encode(value)
        return try fileSystem.writeAtomically(
            data, to: url, permissions: permissions, backupExisting: backupExisting)
    }
}

enum StorageJSON {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
