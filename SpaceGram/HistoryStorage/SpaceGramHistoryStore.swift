import Foundation
import Postbox

public enum SpaceGramHistoryStorageError: Error {
    case unsupportedVersion(Int32)
    case invalidRevisionSequence
    case keyMismatch
    case recordTooLarge(bytes: Int, limit: Int)
}

// Synchronous helpers: call only inside the supplied account's live transaction.
// No transaction is retained, and no ordinary message/history tables are touched.
public enum SpaceGramHistoryStore {
    public static func load(transaction: Transaction, key: SpaceGramHistoryMessageKey) throws -> SpaceGramHistoryRecord? {
        guard let item = transaction.getOrderedItemListItem(collectionId: SpaceGramHistoryCollection.id, itemId: MemoryBuffer(data: key.binaryKey)) else {
            return nil
        }
        return try self.decode(item)
    }

    // Most recently written first. Postbox exposes a full-list read, not pagination.
    public static func readArchive(transaction: Transaction) throws -> [SpaceGramHistoryRecord] {
        return try transaction.getOrderedListItems(collectionId: SpaceGramHistoryCollection.id).map { try self.decode($0) }
    }

    // Browser reads isolate invalid entries without hiding the partial-read failure.
    // The strict readArchive API and all write behavior remain unchanged.
    public static func listRecords(transaction: Transaction) -> (records: [SpaceGramHistoryRecord], unreadableCount: Int) {
        var records: [SpaceGramHistoryRecord] = []
        var unreadableCount = 0
        for item in transaction.getOrderedListItems(collectionId: SpaceGramHistoryCollection.id) {
            do {
                records.append(try self.decode(item))
            } catch {
                unreadableCount += 1
            }
        }
        return (records, unreadableCount)
    }

    @discardableResult
    public static func upsert(transaction: Transaction, record: SpaceGramHistoryRecord) throws -> SpaceGramHistoryRecord {
        try self.validate(record)
        var bounded = record
        bounded.version = SpaceGramHistoryRecord.currentVersion
        bounded.revisions = Array(bounded.revisions.suffix(SpaceGramHistoryCollection.maxRevisionsPerMessage))
        bounded.events = Array(bounded.events.suffix(SpaceGramHistoryCollection.maxEventsPerMessage))
        // Store JSON directly in CodableEntry.data (not CodableEntry.get's Postbox format).
        // This provides a throwing codec and an exact persisted payload byte limit.
        var data = try JSONEncoder().encode(bounded)
        // Prefer the newest snapshot when a long edit history reaches the byte cap.
        // Events can reference evicted revisions; the browser already handles this.
        while data.count > SpaceGramHistoryCollection.maxRecordBytes && bounded.revisions.count > 1 {
            bounded.revisions.removeFirst()
            data = try JSONEncoder().encode(bounded)
        }
        while data.count > SpaceGramHistoryCollection.maxRecordBytes && bounded.events.count > 1 {
            bounded.events.removeFirst()
            data = try JSONEncoder().encode(bounded)
        }
        try self.checkSize(data)
        transaction.addOrMoveToFirstPositionOrderedItemListItem(
            collectionId: SpaceGramHistoryCollection.id,
            item: OrderedItemListEntry(id: MemoryBuffer(data: bounded.key.binaryKey), contents: CodableEntry(data: data)),
            removeTailIfCountExceeds: SpaceGramHistoryCollection.maxArchivedMessages
        )
        return bounded
    }

    @discardableResult
    public static func appendRevision(transaction: Transaction, key: SpaceGramHistoryMessageKey, threadId: Int64? = nil, observedTimestamp: Int64, snapshot: SpaceGramHistorySnapshot) throws -> SpaceGramHistoryRecord {
        var record = try self.load(transaction: transaction, key: key) ?? SpaceGramHistoryRecord(key: key, threadId: threadId)
        guard record.nextRevision < Int64.max else {
            throw SpaceGramHistoryStorageError.invalidRevisionSequence
        }
        record.revisions.append(SpaceGramHistoryRevision(number: record.nextRevision, observedTimestamp: observedTimestamp, snapshot: snapshot))
        record.nextRevision += 1
        if let threadId = threadId {
            record.threadId = threadId
        }
        return try self.upsert(transaction: transaction, record: record)
    }

    @discardableResult
    public static func appendEvent(transaction: Transaction, key: SpaceGramHistoryMessageKey, threadId: Int64? = nil, event: SpaceGramHistoryEvent) throws -> SpaceGramHistoryRecord {
        var record = try self.load(transaction: transaction, key: key) ?? SpaceGramHistoryRecord(key: key, threadId: threadId)
        record.events.append(event)
        if let threadId = threadId {
            record.threadId = threadId
        }
        return try self.upsert(transaction: transaction, record: record)
    }

    public static func remove(transaction: Transaction, key: SpaceGramHistoryMessageKey) {
        transaction.removeOrderedItemListItem(collectionId: SpaceGramHistoryCollection.id, itemId: MemoryBuffer(data: key.binaryKey))
    }

    // Return only assets no longer referenced by this record. The caller removes
    // binary media after the Postbox transaction has committed.
    public static func removeEvent(transaction: Transaction, key: SpaceGramHistoryMessageKey, index: Int, expected: SpaceGramHistoryEvent) throws -> [String] {
        guard var record = try self.load(transaction: transaction, key: key),
              record.events.indices.contains(index), record.events[index] == expected else { return [] }
        let removed = record.events.remove(at: index)
        if let number = removed.revisionNumber, !record.events.contains(where: { $0.revisionNumber == number }) {
            record.revisions.removeAll { $0.number == number }
        }
        let detached = removed.mediaAssetIds ?? []
        if record.events.isEmpty && record.revisions.isEmpty {
            self.remove(transaction: transaction, key: key)
        } else {
            try self.upsert(transaction: transaction, record: record)
        }
        return self.unreferencedAssets(transaction: transaction, candidates: detached)
    }

    public static func removeRevision(transaction: Transaction, key: SpaceGramHistoryMessageKey, number: Int64) throws {
        guard var record = try self.load(transaction: transaction, key: key),
              record.revisions.contains(where: { $0.number == number }) else { return }
        record.revisions.removeAll { $0.number == number }
        if record.events.isEmpty && record.revisions.isEmpty {
            self.remove(transaction: transaction, key: key)
        } else {
            try self.upsert(transaction: transaction, record: record)
        }
    }

    public static func removeMessage(transaction: Transaction, key: SpaceGramHistoryMessageKey) throws -> [String] {
        SpaceGramMessageSnapshotStore.remove(transaction: transaction, key: key)
        guard let record = try self.load(transaction: transaction, key: key) else { return [] }
        self.remove(transaction: transaction, key: key)
        return self.unreferencedAssets(transaction: transaction, candidates: record.events.flatMap { $0.mediaAssetIds ?? [] })
    }

    public static func removePeer(transaction: Transaction, peerId: Int64) -> [String] {
        for received in SpaceGramMessageSnapshotStore.list(transaction: transaction) where received.key.peerId == peerId {
            SpaceGramMessageSnapshotStore.remove(transaction: transaction, key: received.key)
        }
        var assetIds: [String] = []
        for record in self.listRecords(transaction: transaction).records where record.key.peerId == peerId {
            assetIds.append(contentsOf: record.events.flatMap { $0.mediaAssetIds ?? [] })
            self.remove(transaction: transaction, key: record.key)
        }
        return self.unreferencedAssets(transaction: transaction, candidates: assetIds)
    }

    @discardableResult
    public static func clearArchiveWithAssets(transaction: Transaction) -> [String] {
        let assetIds = self.listRecords(transaction: transaction).records.flatMap { $0.events.flatMap { $0.mediaAssetIds ?? [] } }
        self.clearArchive(transaction: transaction)
        return assetIds
    }

    // Fault isolation must not turn an unreadable record into permission to
    // delete a possibly shared asset. Retry orphan cleanup after repair/clear.
    public static func assetReferences(transaction: Transaction) -> (ids: Set<String>, complete: Bool) {
        let result = self.listRecords(transaction: transaction)
        return (Set(result.records.flatMap { $0.events.flatMap { $0.mediaAssetIds ?? [] } }), result.unreadableCount == 0)
    }

    private static func unreferencedAssets(transaction: Transaction, candidates: [String]) -> [String] {
        let result = self.listRecords(transaction: transaction)
        return self.detachedAssets(candidates: candidates, remainingRecords: result.records, complete: result.unreadableCount == 0)
    }

    public static func detachedAssets(candidates: [String], remainingRecords: [SpaceGramHistoryRecord], complete: Bool) -> [String] {
        guard complete else { return [] }
        let references = Set(remainingRecords.flatMap { $0.events.flatMap { $0.mediaAssetIds ?? [] } })
        return Set(candidates).filter { !references.contains($0) }.sorted()
    }

    public static func clearArchive(transaction: Transaction) {
        SpaceGramMessageSnapshotStore.clear(transaction: transaction)
        transaction.replaceOrderedItemListItems(collectionId: SpaceGramHistoryCollection.id, items: [])
    }

    private static func decode(_ item: OrderedItemListEntry) throws -> SpaceGramHistoryRecord {
        try self.checkSize(item.contents.data)
        let decoder = JSONDecoder()
        // Read the version before interpreting a potentially incompatible future schema.
        let header = try decoder.decode(VersionHeader.self, from: item.contents.data)
        guard (1 ... SpaceGramHistoryRecord.currentVersion).contains(header.version) else {
            throw SpaceGramHistoryStorageError.unsupportedVersion(header.version)
        }
        let record = try decoder.decode(SpaceGramHistoryRecord.self, from: item.contents.data)
        try self.validate(record)
        guard record.key.binaryKey == item.id.makeData() else {
            throw SpaceGramHistoryStorageError.keyMismatch
        }
        return record
    }

    private struct VersionHeader: Decodable {
        let version: Int32
    }

    private static func validate(_ record: SpaceGramHistoryRecord) throws {
        guard (1 ... SpaceGramHistoryRecord.currentVersion).contains(record.version) else {
            throw SpaceGramHistoryStorageError.unsupportedVersion(record.version)
        }
        var previous: Int64 = 0
        for revision in record.revisions {
            guard revision.number > previous else {
                throw SpaceGramHistoryStorageError.invalidRevisionSequence
            }
            previous = revision.number
        }
        guard record.nextRevision > previous else {
            throw SpaceGramHistoryStorageError.invalidRevisionSequence
        }
    }

    private static func checkSize(_ data: Data) throws {
        guard data.count <= SpaceGramHistoryCollection.maxRecordBytes else {
            throw SpaceGramHistoryStorageError.recordTooLarge(bytes: data.count, limit: SpaceGramHistoryCollection.maxRecordBytes)
        }
    }
}
