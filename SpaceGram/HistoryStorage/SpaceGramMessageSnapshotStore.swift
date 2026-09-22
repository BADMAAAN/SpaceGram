import Foundation
import Postbox

public struct SpaceGramReceivedMessageSnapshot: Codable, Equatable {
    public let key: SpaceGramHistoryMessageKey
    public let threadId: Int64?
    public let snapshot: SpaceGramHistorySnapshot
    public let receivedTimestamp: Int64?
    public let diagnosticId: String?

    public init(key: SpaceGramHistoryMessageKey, threadId: Int64?, snapshot: SpaceGramHistorySnapshot, receivedTimestamp: Int64? = nil, diagnosticId: String? = nil) {
        self.key = key
        self.threadId = threadId
        self.snapshot = snapshot
        self.receivedTimestamp = receivedTimestamp
        self.diagnosticId = diagnosticId
    }
}

// A separate bounded inbox: receiving new messages must not evict saved deletions
// or turn current versions into edit revisions. Account isolation is Postbox's.
public enum SpaceGramMessageSnapshotStore {
    public static let collectionId: Int32 = 1010

    public static func targetsByResourceId(_ snapshots: [SpaceGramReceivedMessageSnapshot]) -> [String: [SpaceGramReceivedMessageSnapshot]] {
        var result: [String: [SpaceGramReceivedMessageSnapshot]] = [:]
        for received in snapshots {
            for metadata in received.snapshot.media {
                for resourceId in (metadata.resourceIds ?? []).prefix(32) {
                    if result[resourceId]?.contains(where: { $0.key == received.key }) != true {
                        result[resourceId, default: []].append(received)
                    }
                }
            }
        }
        return result
    }

    public static func load(transaction: Transaction, key: SpaceGramHistoryMessageKey) -> SpaceGramReceivedMessageSnapshot? {
        guard let item = transaction.getOrderedItemListItem(collectionId: collectionId, itemId: MemoryBuffer(data: key.binaryKey)),
              let value = decode(item), value.key == key else { return nil }
        return value
    }

    public static func list(transaction: Transaction) -> [SpaceGramReceivedMessageSnapshot] {
        return transaction.getOrderedListItems(collectionId: collectionId).compactMap(decode)
    }

    public static func store(transaction: Transaction, value: SpaceGramReceivedMessageSnapshot) throws {
        if load(transaction: transaction, key: value.key) == value { return }
        let data = try JSONEncoder().encode(value)
        guard data.count <= SpaceGramHistoryCollection.maxRecordBytes else {
            throw SpaceGramHistoryStorageError.recordTooLarge(bytes: data.count, limit: SpaceGramHistoryCollection.maxRecordBytes)
        }
        transaction.addOrMoveToFirstPositionOrderedItemListItem(collectionId: collectionId,
            item: OrderedItemListEntry(id: MemoryBuffer(data: value.key.binaryKey), contents: CodableEntry(data: data)),
            removeTailIfCountExceeds: SpaceGramHistoryCollection.maxArchivedMessages)
    }

    public static func clear(transaction: Transaction) {
        transaction.replaceOrderedItemListItems(collectionId: collectionId, items: [])
    }

    public static func remove(transaction: Transaction, key: SpaceGramHistoryMessageKey) {
        transaction.removeOrderedItemListItem(collectionId: collectionId, itemId: MemoryBuffer(data: key.binaryKey))
    }

    private static func decode(_ item: OrderedItemListEntry) -> SpaceGramReceivedMessageSnapshot? {
        guard item.contents.data.count <= SpaceGramHistoryCollection.maxRecordBytes,
              let value = try? JSONDecoder().decode(SpaceGramReceivedMessageSnapshot.self, from: item.contents.data),
              value.key.binaryKey == item.id.makeData() else { return nil }
        return value
    }
}
