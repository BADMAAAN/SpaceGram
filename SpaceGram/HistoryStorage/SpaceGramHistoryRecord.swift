import Foundation

public struct SpaceGramHistoryRecord: Codable, Equatable {
    public static let currentVersion: Int32 = 3
    public var version: Int32
    public let key: SpaceGramHistoryMessageKey
    public var threadId: Int64?
    public var revisions: [SpaceGramHistoryRevision]
    public var events: [SpaceGramHistoryEvent]
    public var nextRevision: Int64

    public init(key: SpaceGramHistoryMessageKey, threadId: Int64? = nil) {
        self.version = Self.currentVersion
        self.key = key
        self.threadId = threadId
        self.revisions = []
        self.events = []
        self.nextRevision = 1
    }
}

public struct SpaceGramHistoryRevision: Codable, Equatable {
    public let number: Int64
    public let observedTimestamp: Int64
    public let snapshot: SpaceGramHistorySnapshot

    public init(number: Int64, observedTimestamp: Int64, snapshot: SpaceGramHistorySnapshot) {
        self.number = number
        self.observedTimestamp = observedTimestamp
        self.snapshot = snapshot
    }
}

// Caller-supplied OLD content. Binary media bytes are stored by SpaceGramMediaArchive;
// nativeMediaPayload retains only Telegram's account-local media descriptor.
// All timestamps use Unix seconds; entity offsets/lengths use UTF-16 code units.
public struct SpaceGramHistorySnapshot: Codable, Equatable {
    public var text: String
    public var originalMessageTimestamp: Int64
    public var serverEditTimestamp: Int64?
    public var authorPeerId: Int64?
    public var entities: [SpaceGramHistoryEntity]
    public var forwardMetadata: [String: String]?
    public var replyMetadata: [String: String]?
    public var threadMetadata: [String: String]?
    public var media: [SpaceGramHistoryMediaMetadata]
    public var groupingKey: Int64?
    public var hasMediaSpoiler: Bool?

    public init(text: String, originalMessageTimestamp: Int64) {
        self.text = text
        self.originalMessageTimestamp = originalMessageTimestamp
        self.entities = []
        self.media = []
    }
}

public struct SpaceGramHistoryEntity: Codable, Equatable {
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

public struct SpaceGramHistoryMediaMetadata: Codable, Equatable {
    public var type: String
    public var text: String?
    public var filename: String?
    public var size: Int64?
    public var duration: Double?
    public var width: Int32?
    public var height: Int32?
    // Optional v2 additions; old snapshots continue to decode unchanged.
    public var mimeType: String?
    public var isVoice: Bool?
    public var isInstantVideo: Bool?
    public var isAnimated: Bool?
    public var stickerText: String?
    public var resourceIds: [String]?
    // Postbox-encoded TelegramMediaImage/TelegramMediaFile. This is kept only in
    // the owning account's Postbox and is never logged or treated as media bytes.
    public var nativeMediaPayload: Data?
    public var identifiers: [String: String]

    public init(type: String) {
        self.type = type
        self.identifiers = [:]
    }
}

public enum SpaceGramHistoryEventType: String, Codable {
    case edit
    case delete
    case cleanup
}

public enum SpaceGramHistoryReason: String, Codable {
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

public struct SpaceGramHistoryEvent: Codable, Equatable {
    public let type: SpaceGramHistoryEventType
    // Stable caller-defined source name, e.g. a future hook or synchronization path.
    public let source: String
    public let reason: SpaceGramHistoryReason
    public let observedTimestamp: Int64
    public let revisionNumber: Int64?
    // V2 fields are optional so v1 records decode without rewriting on reads.
    public var mediaCaptureId: String?
    public var mediaAssetIds: [String]?
    public var mediaResourceIds: [String]?

    public init(type: SpaceGramHistoryEventType, source: String, reason: SpaceGramHistoryReason, observedTimestamp: Int64, revisionNumber: Int64? = nil) {
        self.type = type
        self.source = source
        self.reason = reason
        self.observedTimestamp = observedTimestamp
        self.revisionNumber = revisionNumber
    }
}
