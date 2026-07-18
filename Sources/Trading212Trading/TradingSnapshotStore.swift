import Foundation
import Trading212Core

public struct TradingSnapshotStore: Sendable {
    private let fileSystem: any FileSystem

    public init(fileSystem: any FileSystem = LocalFileSystem()) {
        self.fileSystem = fileSystem
    }

    @discardableResult
    public func write(
        _ snapshot: TradingSnapshotDocument,
        to url: URL,
        backupExisting: Bool = false
    ) throws -> URL? {
        let data = try TradingSnapshotCodec.encode(snapshot)
        return try fileSystem.writeAtomically(
            data,
            to: url,
            permissions: .ownerReadWrite,
            backupExisting: backupExisting
        )
    }

    public func read(
        from url: URL,
        expectedEnvironment: Trading212Environment? = nil,
        expectedAccountID: String? = nil
    ) throws -> DecodedTradingSnapshot {
        try TradingSnapshotCodec.decode(
            fileSystem.data(at: url),
            expectedEnvironment: expectedEnvironment,
            expectedAccountID: expectedAccountID
        )
    }
}

public enum TradingFileNames {
    public static func snapshot(
        kind: TradingSnapshotDocument.Kind,
        environment: Trading212Environment,
        at date: Date
    ) -> String {
        "\(kind.rawValue)-\(environment.rawValue)-\(timestamp(date)).json"
    }

    public static func receipt(action: TradingAction, id: UUID) -> String {
        "\(action.rawValue)-\(id.uuidString.lowercased()).json"
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: date)
    }
}
