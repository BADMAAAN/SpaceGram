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
    // Telegram sends immediately below 10 seconds. Recompute at submission
    // after upload, leaving two seconds for normal transit and clock rounding.
    public static let minimumDelay: Int32 = 12

    public static func delay(mediaBytes: Int64?) -> Int32 {
        // Upload time is handled at submit, not estimated from file size twice.
        return minimumDelay
    }

    public static func timestamp(now: Int64, ghost: SpaceGramGhostMode, enabled: Bool, mediaBytes: Int64?) -> Int32? {
        guard ghost.enabled, enabled, now >= 0 else { return nil }
        let (value, overflow) = now.addingReportingOverflow(Int64(delay(mediaBytes: mediaBytes)))
        guard !overflow else { return nil }
        return Int32(exactly: value)
    }
}
