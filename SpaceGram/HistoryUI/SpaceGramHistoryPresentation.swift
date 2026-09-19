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
        return ngI18n(detail ? "SpaceGram.History.EditEvent" : "SpaceGram.History.Edited", lang)
    case .delete:
        return "🗑 " + ngI18n(event.reason == .serverDelete ? "SpaceGram.History.ServerDeleted" : "SpaceGram.History.Deleted", lang)
    case .cleanup:
        return ngI18n(event.reason == .mediaArchive ? "SpaceGram.MediaCaptured" : "SpaceGram.History.Cleanup", lang)
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

func spaceGramHistoryText(_ revision: SpaceGramHistoryRevision?, lang: String) -> String {
    guard let revision = revision else {
        return ngI18n("SpaceGram.History.TextMissing", lang)
    }
    return revision.snapshot.text.isEmpty ? ngI18n("SpaceGram.History.NoText", lang) : revision.snapshot.text
}

func spaceGramHistoryPreview(_ record: SpaceGramHistoryRecord, event: SpaceGramHistoryEvent? = nil, lang: String) -> String {
    let event = event ?? spaceGramHistoryLatestEvent(record)
    let revision = event == nil ? record.revisions.last : record.revisions.first { $0.number == event?.revisionNumber }
    return String(spaceGramHistoryText(revision, lang: lang).split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").prefix(180))
}

func spaceGramHistoryTimeline(_ record: SpaceGramHistoryRecord, lang: String = "en") -> [SpaceGramHistoryTimelineItem] {
    return SpaceGramHistoryPresentationModel.timeline(record).map { item in
        return SpaceGramHistoryTimelineItem(
            timestamp: item.timestamp,
            title: item.event.map { spaceGramHistoryEventTitle($0, detail: true, lang: lang) } ?? ngI18n("SpaceGram.History.SavedRevision", lang),
            text: spaceGramHistoryText(item.revision, lang: lang),
            eventIndex: item.eventIndex,
            revisionNumber: item.revision?.number,
            snapshot: item.revision?.snapshot
        )
    }
}

func spaceGramHistoryDate(_ timestamp: Int64, formatter: DateFormatter) -> String {
    // A decodable Int64 need not be a date Foundation can usefully display.
    guard timestamp >= -62135596800 && timestamp <= 253402300799 else {
        return "Unknown time"
    }
    return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
}
