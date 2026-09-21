import Foundation

/// A read-only projection of schema v2. Never creates Telegram messages.
public struct SpaceGramHistoryPresentationItem {
    public let timestamp: Int64
    public let eventIndex: Int?
    public let event: SpaceGramHistoryEvent?
    public let revision: SpaceGramHistoryRevision?
}

public enum SpaceGramHistoryPresentationModel {
    public static func editRevisions(_ record: SpaceGramHistoryRecord) -> [SpaceGramHistoryRevision] {
        let numbers = Set(record.events.filter { $0.type == .edit }.compactMap(\.revisionNumber))
        // Capture/delete snapshots are not prior edits. Sequence numbers also
        // retain A -> B -> A when edits share a timestamp or the clock changes.
        return record.revisions.filter { numbers.contains($0.number) }.sorted { $0.number < $1.number }
    }

    public static func timeline(_ record: SpaceGramHistoryRecord) -> [SpaceGramHistoryPresentationItem] {
        var items = record.events.enumerated().map { index, event in
            SpaceGramHistoryPresentationItem(timestamp: event.observedTimestamp, eventIndex: index, event: event, revision: record.revisions.first { $0.number == event.revisionNumber })
        }
        let referenced = Set(record.events.compactMap { $0.revisionNumber })
        for revision in record.revisions where !referenced.contains(revision.number) {
            items.append(SpaceGramHistoryPresentationItem(timestamp: revision.observedTimestamp, eventIndex: nil, event: nil, revision: revision))
        }
        return items.enumerated().sorted {
            $0.element.timestamp == $1.element.timestamp ? $0.offset < $1.offset : $0.element.timestamp < $1.element.timestamp
        }.map { $0.element }
    }

    public static func deletedSnapshot(_ record: SpaceGramHistoryRecord) -> SpaceGramHistorySnapshot? {
        guard let event = record.events.enumerated().filter({ $0.element.type == .delete }).max(by: {
            $0.element.observedTimestamp == $1.element.observedTimestamp ? $0.offset < $1.offset : $0.element.observedTimestamp < $1.element.observedTimestamp
        })?.element else { return nil }
        // Do not substitute an unrelated revision if this event's text expired.
        return record.revisions.first { $0.number == event.revisionNumber }?.snapshot
    }
}
