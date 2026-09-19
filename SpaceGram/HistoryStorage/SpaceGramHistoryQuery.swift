import Foundation

public enum SpaceGramHistoryKind: Int, CaseIterable, Equatable {
    case all, edited, deleted, media
}

/// Used by the browser on its Postbox worker; no file reads or UI dependencies.
public enum SpaceGramHistoryQuery {
    public static func matches(_ record: SpaceGramHistoryRecord, kind: SpaceGramHistoryKind = .all, peerId: Int64? = nil, query: String = "", peerTitles: [String] = []) -> Bool {
        if let peerId, record.key.peerId != peerId { return false }
        switch kind {
        case .all: break
        case .edited: if !record.events.contains(where: { $0.type == .edit }) { return false }
        case .deleted: if !record.events.contains(where: { $0.type == .delete }) { return false }
        case .media:
            if !record.revisions.contains(where: { !$0.snapshot.media.isEmpty }) && !record.events.contains(where: { $0.mediaCaptureId != nil || !($0.mediaAssetIds ?? []).isEmpty }) { return false }
        }
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        if peerTitles.contains(where: { $0.localizedCaseInsensitiveContains(query) }) { return true }
        if record.revisions.contains(where: { $0.snapshot.text.localizedCaseInsensitiveContains(query) || $0.snapshot.media.contains(where: { $0.filename?.localizedCaseInsensitiveContains(query) == true }) }) { return true }
        return record.events.contains { $0.type.rawValue.localizedCaseInsensitiveContains(query) || $0.reason.rawValue.localizedCaseInsensitiveContains(query) }
    }
}
