import Foundation
import QwengramStrings
import QwengramHistoryStorage

struct QwengramHistoryTimelineItem {
    let timestamp: Int64
    let title: String
    let text: String
    let eventIndex: Int?
    let revisionNumber: Int64?
    let snapshot: QwengramHistorySnapshot?
}

func qwengramHistoryEventTitle(_ event: QwengramHistoryEvent, detail: Bool, lang: String = "en") -> String {
    switch event.type {
    case .edit:
        return detail ? "Edit" : "Edited"
    case .delete:
        return event.reason == .serverDelete ? "Deleted on server" : "Deleted"
    case .cleanup:
        return event.reason == .mediaArchive ? ngI18n("Qwengram.MediaCaptured", lang) : "Cleanup"
    }
}

func qwengramHistoryLatestEvent(_ record: QwengramHistoryRecord) -> QwengramHistoryEvent? {
    return record.events.enumerated().max {
        if $0.element.observedTimestamp != $1.element.observedTimestamp {
            return $0.element.observedTimestamp < $1.element.observedTimestamp
        }
        return $0.offset < $1.offset
    }?.element
}

func qwengramHistoryLatestTimestamp(_ record: QwengramHistoryRecord) -> Int64 {
    return (record.events.map { $0.observedTimestamp } + record.revisions.map { $0.observedTimestamp }).max() ?? 0
}

func qwengramHistoryNewestFirst(_ records: [QwengramHistoryRecord]) -> [QwengramHistoryRecord] {
    return records.enumerated().sorted {
        let lhs = qwengramHistoryLatestTimestamp($0.element)
        let rhs = qwengramHistoryLatestTimestamp($1.element)
        // Retain Postbox's last-write order for observations in the same second.
        return lhs == rhs ? $0.offset < $1.offset : lhs > rhs
    }.map { $0.element }
}

func qwengramHistoryText(_ revision: QwengramHistoryRevision?) -> String {
    guard let revision = revision else {
        return "Saved text is no longer available."
    }
    return revision.snapshot.text.isEmpty ? "No text (media or empty message)." : revision.snapshot.text
}

func qwengramHistoryPreview(_ record: QwengramHistoryRecord, event: QwengramHistoryEvent? = nil) -> String {
    let event = event ?? qwengramHistoryLatestEvent(record)
    let revision = record.revisions.first { $0.number == event?.revisionNumber } ?? record.revisions.last
    return String(qwengramHistoryText(revision).split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").prefix(180))
}

func qwengramHistoryTimeline(_ record: QwengramHistoryRecord, lang: String = "en") -> [QwengramHistoryTimelineItem] {
    var items = record.events.enumerated().map { index, event in
        let revision = record.revisions.first { $0.number == event.revisionNumber }
        return QwengramHistoryTimelineItem(
            timestamp: event.observedTimestamp,
            title: qwengramHistoryEventTitle(event, detail: true, lang: lang),
            text: qwengramHistoryText(revision),
            eventIndex: index,
            revisionNumber: revision?.number,
            snapshot: revision?.snapshot
        )
    }
    // Revisions and events have independent retention limits. Show unpaired
    // snapshots too, and never invent an event type when the event is absent.
    let referencedRevisions = Set(record.events.compactMap { $0.revisionNumber })
    for revision in record.revisions where !referencedRevisions.contains(revision.number) {
        items.append(QwengramHistoryTimelineItem(timestamp: revision.observedTimestamp, title: "Saved revision", text: qwengramHistoryText(revision), eventIndex: nil, revisionNumber: revision.number, snapshot: revision.snapshot))
    }
    return items.enumerated().sorted {
        return $0.element.timestamp == $1.element.timestamp ? $0.offset < $1.offset : $0.element.timestamp < $1.element.timestamp
    }.map { $0.element }
}

func qwengramHistoryDate(_ timestamp: Int64, formatter: DateFormatter) -> String {
    // A decodable Int64 need not be a date Foundation can usefully display.
    guard timestamp >= -62135596800 && timestamp <= 253402300799 else {
        return "Unknown time"
    }
    return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
}
