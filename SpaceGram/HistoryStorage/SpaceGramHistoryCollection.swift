import Foundation

public enum SpaceGramHistoryCollection {
    // SpaceGram-local reservation: application-specific ordered collection 1000 + 9.
    // Keep this literal independent of TelegramCore. See STORAGE.md.
    public static let id: Int32 = 1009
    public static let maxArchivedMessages = 1000
    public static let maxRevisionsPerMessage = 20
    public static let maxEventsPerMessage = 100
    public static let maxRecordBytes = 256 * 1024
}

public struct SpaceGramHistoryMessageKey: Codable, Equatable {
    // Full packed PeerId.toInt64() value, including the peer namespace.
    public let peerId: Int64
    public let namespace: Int32
    public let id: Int32

    public init(peerId: Int64, namespace: Int32, id: Int32) {
        self.peerId = peerId
        self.namespace = namespace
        self.id = id
    }

    // Exactly 16 bytes: signed two's-complement integers in big-endian order.
    // Account is implicit in Postbox; threadId is deliberately not part of identity.
    public var binaryKey: Data {
        var data = Data()
        var peer = self.peerId.bigEndian
        var namespace = self.namespace.bigEndian
        var id = self.id.bigEndian
        withUnsafeBytes(of: &peer) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &namespace) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: &id) { data.append(contentsOf: $0) }
        return data
    }
}
