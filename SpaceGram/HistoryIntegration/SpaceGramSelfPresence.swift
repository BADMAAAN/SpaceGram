import Foundation
import Postbox
import SpaceGramSettingsSignal
import SwiftSignalKit
import TelegramApi

private let spaceGramSelfPresenceKey = ValueBoxKey("spacegram.self-presence.v1")

private struct SpaceGramSelfPresenceRecord: Codable {
    let timestamp: Int32
}

// Only server was_online or a successful online RPC enters this store. The
// account's synthetic .present(Int32.max - 1) and offline heartbeats never do.
func spaceGramStoreSelfPresence(transaction: Transaction, timestamp: Int32, allowRollback: Bool = false) {
    guard timestamp > 0, timestamp < Int32.max - 1 else { return }
    let previous = transaction.getPreferencesEntry(key: spaceGramSelfPresenceKey)?.get(SpaceGramSelfPresenceRecord.self)
    guard allowRollback || (previous?.timestamp ?? 0) < timestamp else { return }
    transaction.setPreferencesEntry(key: spaceGramSelfPresenceKey, value: PreferencesEntry(SpaceGramSelfPresenceRecord(timestamp: timestamp)))
}

func spaceGramCaptureSelfPresence(transaction: Transaction, status: Api.UserStatus) {
    if case let .userStatusOffline(data) = status {
        // MARK: NAGRAM — this is an authoritative server value. A transient
        // online status may resolve back to an older was_online, so do not keep
        // a newer local observation in preference to the server response.
        spaceGramStoreSelfPresence(transaction: transaction, timestamp: data.wasOnline, allowRollback: true)
    }
}

public func spaceGramSelfPresenceSignal(postbox: Postbox) -> Signal<TelegramUserPresence?, NoError> {
    let key = PostboxViewKey.preferences(keys: Set([spaceGramSelfPresenceKey]))
    return combineLatest(postbox.combinedView(keys: [key]), spaceGramSuppressOnlinePresenceSignal())
    |> map { views, ghost -> TelegramUserPresence? in
        guard ghost else { return nil }
        let value = (views.views[key] as? PreferencesView)?.values[spaceGramSelfPresenceKey]?.get(SpaceGramSelfPresenceRecord.self)
        return TelegramUserPresence(status: value.map { .present(until: $0.timestamp) } ?? .none, lastActivity: 0)
    }
    |> distinctUntilChanged
}
