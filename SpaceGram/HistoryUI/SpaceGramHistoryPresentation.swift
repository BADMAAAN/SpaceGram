import Foundation
import SpaceGramStrings
import SpaceGramHistoryStorage

struct SpaceGramHistoryTimelineItem {
    let timestamp: Int64
    let title: String
    let text: String
    let eventIndex: Int?
    let revisionNumber: Int64?
    let snapshot: SpaceGramHistorySnapshot?
}

func spaceGramHistoryEventTitle(_ event: SpaceGramHistoryEvent, detail: Bool, lang: String = "en") -> String {
    switch event.type {
    case .edit:
        return detail ? "Edit" : "Edited"
    case .delete:
        return event.reason == .serverDelete ? "Deleted on server" : "Deleted"
    case .cleanup:
        return event.reason == .mediaArchive ? ngI18n("SpaceGram.MediaCaptured", lang) : "Cleanup"
    }
}

func spaceGramHistoryLatestEvent(_ record: SpaceGramHistoryRecord) -> SpaceGramHistoryEvent? {
    return record.events.enumerated().max {
        if $0.element.observedTimestamp != $1.element.observedTimestamp {
            return $0.element.observedTimestamp < $1.element.observedTimestamp
        }
        return $0.offset < $1.offset
    }?.element
}

func spaceGramHistoryLatestTimestamp(_ record: SpaceGramHistoryRecord) -> Int64 {
    return (record.events.map { $0.observedTimestamp } + record.revisions.map { $0.observedTimestamp }).max() ?? 0
}

func spaceGramHistoryNewestFirst(_ records: [SpaceGramHistoryRecord]) -> [SpaceGramHistoryRecord] {
    return records.enumerated().sorted {
        let lhs = spaceGramHistoryLatestTimestamp($0.element)
        let rhs = spaceGramHistoryLatestTimestamp($1.element)
        // Retain Postbox's last-write order for observations in the same second.
        return lhs == rhs ? $0.offset < $1.offset : lhs > rhs
    }.map { $0.element }
}

func spaceGramHistoryText(_ revision: SpaceGramHistoryRevision?) -> String {
    guard let revision = revision else {
        return "Saved text is no longer available."
    }
    return revision.snapshot.text.isEmpty ? "No text (media or empty message)." : revision.snapshot.text
}

func spaceGramHistoryPreview(_ record: SpaceGramHistoryRecord, event: SpaceGramHistoryEvent? = nil) -> String {
    let event = event ?? spaceGramHistoryLatestEvent(record)
    let revision = record.revisions.first { $0.number == event?.revisionNumber } ?? record.revisions.last
    return String(spaceGramHistoryText(revision).split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").prefix(180))
}

func spaceGramHistoryTimeline(_ record: SpaceGramHistoryRecord, lang: String = "en") -> [SpaceGramHistoryTimelineItem] {
    var items = record.events.enumerated().map { index, event in
        let revision = record.revisions.first { $0.number == event.revisionNumber }
        return SpaceGramHistoryTimelineItem(
            timestamp: event.observedTimestamp,
            title: spaceGramHistoryEventTitle(event, detail: true, lang: lang),
            text: spaceGramHistoryText(revision),
            eventIndex: index,
            revisionNumber: revision?.number,
            snapshot: revision?.snapshot
        )
    }
    // Revisions and events have independent retention limits. Show unpaired
    // snapshots too, and never invent an event type when the event is absent.
    let referencedRevisions = Set(record.events.compactMap { $0.revisionNumber })
    for revision in record.revisions where !referencedRevisions.contains(revision.number) {
        items.append(SpaceGramHistoryTimelineItem(timestamp: revision.observedTimestamp, title: "Saved revision", text: spaceGramHistoryText(revision), eventIndex: nil, revisionNumber: revision.number, snapshot: revision.snapshot))
    }
    return items.enumerated().sorted {
        return $0.element.timestamp == $1.element.timestamp ? $0.offset < $1.offset : $0.element.timestamp < $1.element.timestamp
    }.map { $0.element }
}

func spaceGramHistoryDate(_ timestamp: Int64, formatter: DateFormatter) -> String {
    // A decodable Int64 need not be a date Foundation can usefully display.
    guard timestamp >= -62135596800 && timestamp <= 253402300799 else {
        return "Unknown time"
    }
    return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
}
