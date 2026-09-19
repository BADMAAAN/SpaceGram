import Foundation

public struct SpaceGramMediaArchivePolicy: Codable, Equatable {
    public static let storagePresets: [Int64] = [256, 512, 1024, 2048].map { $0 * 1024 * 1024 }
    public static let retentionPresets = [7, 30, 90]
    public static let `default` = SpaceGramMediaArchivePolicy(storageLimitBytes: 512 * 1024 * 1024, retentionDays: 30, automaticCleanup: true)

    public let version: Int
    public let storageLimitBytes: Int64
    public let retentionDays: Int
    public let automaticCleanup: Bool

    public init(storageLimitBytes: Int64, retentionDays: Int, automaticCleanup: Bool) {
        self.version = 1
        self.storageLimitBytes = storageLimitBytes
        self.retentionDays = retentionDays
        self.automaticCleanup = automaticCleanup
    }

    public var isValid: Bool {
        return version == 1 && Self.storagePresets.contains(storageLimitBytes) && Self.retentionPresets.contains(retentionDays)
    }
}

public struct SpaceGramMediaArchiveUsage {
    public let bytes: Int64
    public let assetCount: Int
    public let policy: SpaceGramMediaArchivePolicy
}
