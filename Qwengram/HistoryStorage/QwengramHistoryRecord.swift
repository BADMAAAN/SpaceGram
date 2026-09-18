import Foundation

public struct QwengramHistoryRecord: Codable, Equatable {
    public static let currentVersion: Int32 = 2
    public var version: Int32
    public let key: QwengramHistoryMessageKey
    public var threadId: Int64?
    public var revisions: [QwengramHistoryRevision]
    public var events: [QwengramHistoryEvent]
    public var nextRevision: Int64

    public init(key: QwengramHistoryMessageKey, threadId: Int64? = nil) {
        self.version = Self.currentVersion
        self.key = key
        self.threadId = threadId
        self.revisions = []
        self.events = []
        self.nextRevision = 1
    }
}

public struct QwengramHistoryRevision: Codable, Equatable {
    public let number: Int64
    public let observedTimestamp: Int64
    public let snapshot: QwengramHistorySnapshot

    public init(number: Int64, observedTimestamp: Int64, snapshot: QwengramHistorySnapshot) {
        self.number = number
        self.observedTimestamp = observedTimestamp
        self.snapshot = snapshot
    }
}

// Caller-supplied OLD content. No runtime Message or media bytes are serialized.
// All timestamps use Unix seconds; entity offsets/lengths use UTF-16 code units.
public struct QwengramHistorySnapshot: Codable, Equatable {
    public var text: String
    public var originalMessageTimestamp: Int64
    public var serverEditTimestamp: Int64?
    public var authorPeerId: Int64?
    public var entities: [QwengramHistoryEntity]
    public var forwardMetadata: [String: String]?
    public var replyMetadata: [String: String]?
    public var threadMetadata: [String: String]?
    public var media: [QwengramHistoryMediaMetadata]

    public init(text: String, originalMessageTimestamp: Int64) {
        self.text = text
        self.originalMessageTimestamp = originalMessageTimestamp
        self.entities = []
        self.media = []
    }
}

public struct QwengramHistoryEntity: Codable, Equatable {
    public var type: String
    public var offset: Int32
    public var length: Int32
    // E.g. URL, language, packed peer id, custom emoji id; never runtime objects.
    public var attributes: [String: String]

    public init(type: String, offset: Int32, length: Int32, attributes: [String: String] = [:]) {
        self.type = type
        self.offset = offset
        self.length = length
        self.attributes = attributes
    }
}

public struct QwengramHistoryMediaMetadata: Codable, Equatable {
    public var type: String
    public var text: String?
    public var filename: String?
    public var size: Int64?
    public var duration: Double?
    public var width: Int32?
    public var height: Int32?
    // Descriptive identifiers only: no access hashes, credentials, file references,
    // local paths, resource retention, or encoded media payloads.
    public var identifiers: [String: String]

    public init(type: String) {
        self.type = type
        self.identifiers = [:]
    }
}

public enum QwengramHistoryEventType: String, Codable {
    case edit
    case delete
    case cleanup
}

public enum QwengramHistoryReason: String, Codable {
    case edit
    case syncDetectedEdit
    case serverDelete
    case localDeleteForMe
    case localDeleteForEveryone
    case clearHistory
    case autoDelete
    case validationCleanup
    case mediaArchive
}

public struct QwengramHistoryEvent: Codable, Equatable {
    public let type: QwengramHistoryEventType
    // Stable caller-defined source name, e.g. a future hook or synchronization path.
    public let source: String
    public let reason: QwengramHistoryReason
    public let observedTimestamp: Int64
    public let revisionNumber: Int64?
    // V2 fields are optional so v1 records decode without rewriting on reads.
    public var mediaCaptureId: String?
    public var mediaAssetIds: [String]?

    public init(type: QwengramHistoryEventType, source: String, reason: QwengramHistoryReason, observedTimestamp: Int64, revisionNumber: Int64? = nil) {
        self.type = type
        self.source = source
        self.reason = reason
        self.observedTimestamp = observedTimestamp
        self.revisionNumber = revisionNumber
    }
}
