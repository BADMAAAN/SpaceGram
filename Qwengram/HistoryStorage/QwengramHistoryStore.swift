import Foundation
import Postbox

public enum QwengramHistoryStorageError: Error {
    case unsupportedVersion(Int32)
    case invalidRevisionSequence
    case keyMismatch
    case recordTooLarge(bytes: Int, limit: Int)
}

// Synchronous helpers: call only inside the supplied account's live transaction.
// No transaction is retained, and no ordinary message/history tables are touched.
public enum QwengramHistoryStore {
    public static func load(transaction: Transaction, key: QwengramHistoryMessageKey) throws -> QwengramHistoryRecord? {
        guard let item = transaction.getOrderedItemListItem(collectionId: QwengramHistoryCollection.id, itemId: MemoryBuffer(data: key.binaryKey)) else {
            return nil
        }
        return try self.decode(item)
    }

    // Most recently written first. Postbox exposes a full-list read, not pagination.
    public static func readArchive(transaction: Transaction) throws -> [QwengramHistoryRecord] {
        return try transaction.getOrderedListItems(collectionId: QwengramHistoryCollection.id).map { try self.decode($0) }
    }

    // Browser reads isolate invalid entries without hiding the partial-read failure.
    // The strict readArchive API and all write behavior remain unchanged.
    public static func listRecords(transaction: Transaction) -> (records: [QwengramHistoryRecord], unreadableCount: Int) {
        var records: [QwengramHistoryRecord] = []
        var unreadableCount = 0
        for item in transaction.getOrderedListItems(collectionId: QwengramHistoryCollection.id) {
            do {
                records.append(try self.decode(item))
            } catch {
                unreadableCount += 1
            }
        }
        return (records, unreadableCount)
    }

    @discardableResult
    public static func upsert(transaction: Transaction, record: QwengramHistoryRecord) throws -> QwengramHistoryRecord {
        try self.validate(record)
        var bounded = record
        bounded.version = QwengramHistoryRecord.currentVersion
        bounded.revisions = Array(bounded.revisions.suffix(QwengramHistoryCollection.maxRevisionsPerMessage))
        bounded.events = Array(bounded.events.suffix(QwengramHistoryCollection.maxEventsPerMessage))
        // Store JSON directly in CodableEntry.data (not CodableEntry.get's Postbox format).
        // This provides a throwing codec and an exact persisted payload byte limit.
        var data = try JSONEncoder().encode(bounded)
        // Prefer the newest snapshot when a long edit history reaches the byte cap.
        // Events can reference evicted revisions; the browser already handles this.
        while data.count > QwengramHistoryCollection.maxRecordBytes && bounded.revisions.count > 1 {
            bounded.revisions.removeFirst()
            data = try JSONEncoder().encode(bounded)
        }
        while data.count > QwengramHistoryCollection.maxRecordBytes && bounded.events.count > 1 {
            bounded.events.removeFirst()
            data = try JSONEncoder().encode(bounded)
        }
        try self.checkSize(data)
        transaction.addOrMoveToFirstPositionOrderedItemListItem(
            collectionId: QwengramHistoryCollection.id,
            item: OrderedItemListEntry(id: MemoryBuffer(data: bounded.key.binaryKey), contents: CodableEntry(data: data)),
            removeTailIfCountExceeds: QwengramHistoryCollection.maxArchivedMessages
        )
        return bounded
    }

    @discardableResult
    public static func appendRevision(transaction: Transaction, key: QwengramHistoryMessageKey, threadId: Int64? = nil, observedTimestamp: Int64, snapshot: QwengramHistorySnapshot) throws -> QwengramHistoryRecord {
        var record = try self.load(transaction: transaction, key: key) ?? QwengramHistoryRecord(key: key, threadId: threadId)
        guard record.nextRevision < Int64.max else {
            throw QwengramHistoryStorageError.invalidRevisionSequence
        }
        record.revisions.append(QwengramHistoryRevision(number: record.nextRevision, observedTimestamp: observedTimestamp, snapshot: snapshot))
        record.nextRevision += 1
        if let threadId = threadId {
            record.threadId = threadId
        }
        return try self.upsert(transaction: transaction, record: record)
    }

    @discardableResult
    public static func appendEvent(transaction: Transaction, key: QwengramHistoryMessageKey, threadId: Int64? = nil, event: QwengramHistoryEvent) throws -> QwengramHistoryRecord {
        var record = try self.load(transaction: transaction, key: key) ?? QwengramHistoryRecord(key: key, threadId: threadId)
        record.events.append(event)
        if let threadId = threadId {
            record.threadId = threadId
        }
        return try self.upsert(transaction: transaction, record: record)
    }

    public static func remove(transaction: Transaction, key: QwengramHistoryMessageKey) {
        transaction.removeOrderedItemListItem(collectionId: QwengramHistoryCollection.id, itemId: MemoryBuffer(data: key.binaryKey))
    }

    public static func clearArchive(transaction: Transaction) {
        transaction.replaceOrderedItemListItems(collectionId: QwengramHistoryCollection.id, items: [])
    }

    private static func decode(_ item: OrderedItemListEntry) throws -> QwengramHistoryRecord {
        try self.checkSize(item.contents.data)
        let decoder = JSONDecoder()
        // Read the version before interpreting a potentially incompatible future schema.
        let header = try decoder.decode(VersionHeader.self, from: item.contents.data)
        guard (1 ... QwengramHistoryRecord.currentVersion).contains(header.version) else {
            throw QwengramHistoryStorageError.unsupportedVersion(header.version)
        }
        let record = try decoder.decode(QwengramHistoryRecord.self, from: item.contents.data)
        try self.validate(record)
        guard record.key.binaryKey == item.id.makeData() else {
            throw QwengramHistoryStorageError.keyMismatch
        }
        return record
    }

    private struct VersionHeader: Decodable {
        let version: Int32
    }

    private static func validate(_ record: QwengramHistoryRecord) throws {
        guard (1 ... QwengramHistoryRecord.currentVersion).contains(record.version) else {
            throw QwengramHistoryStorageError.unsupportedVersion(record.version)
        }
        var previous: Int64 = 0
        for revision in record.revisions {
            guard revision.number > previous else {
                throw QwengramHistoryStorageError.invalidRevisionSequence
            }
            previous = revision.number
        }
        guard record.nextRevision > previous else {
            throw QwengramHistoryStorageError.invalidRevisionSequence
        }
    }

    private static func checkSize(_ data: Data) throws {
        guard data.count <= QwengramHistoryCollection.maxRecordBytes else {
            throw QwengramHistoryStorageError.recordTooLarge(bytes: data.count, limit: QwengramHistoryCollection.maxRecordBytes)
        }
    }
}
