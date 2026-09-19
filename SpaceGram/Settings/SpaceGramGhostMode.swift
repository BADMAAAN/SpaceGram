import Foundation

/// One aggregate over the existing preferences, not a second Ghost state.
public struct SpaceGramGhostMode: Equatable {
    public let enabled: Bool
    public let reads: Bool
    public let stories: Bool
    public let presence: Bool
    public let activity: Bool

    public init(enabled: Bool, reads: Bool, stories: Bool, presence: Bool, activity: Bool) {
        self.enabled = enabled
        self.reads = reads
        self.stories = stories
        self.presence = presence
        self.activity = activity
    }

    public var isFull: Bool { enabled && reads && stories && presence && activity }
}

/// Scheduling policy inspired by AyuGram's documented behavior:
/// https://docs.ayugram.one/shared/ghost/#schedule-messages
/// Native Telegram owns persistence, retries, cancellation and sending.
public enum SpaceGramDelayedSendPolicy {
    public static func delay(mediaBytes: Int64?) -> Int32 {
        guard let mediaBytes, mediaBytes >= 0 else { return 12 }
        let seconds = max(6.0, ceil(Double(mediaBytes) / 1_048_576.0 * 4.5))
        // Bound malformed metadata before conversion; no overflow or years-long delay.
        return Int32(min(seconds, 86_400.0))
    }

    public static func timestamp(now: Int64, ghost: SpaceGramGhostMode, enabled: Bool, mediaBytes: Int64?) -> Int32? {
        guard ghost.isFull, enabled, now >= 0 else { return nil }
        let (value, overflow) = now.addingReportingOverflow(Int64(delay(mediaBytes: mediaBytes)))
        guard !overflow else { return nil }
        return Int32(exactly: value)
    }
}
