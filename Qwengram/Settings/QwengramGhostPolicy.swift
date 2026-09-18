import Foundation

// No Telegram types or network effects: hooks consult the same effective policy.
public enum QwengramGhostPolicy {
    public static var suppressAutomaticReads: Bool {
        let settings = QwengramSettings.shared
        return settings.qwengramEnabled && settings.suppressAutomaticReads
    }

    public static var suppressChatActivity: Bool {
        let settings = QwengramSettings.shared
        return settings.qwengramEnabled && settings.hideChatActivity
    }

    public static var suppressStoryViews: Bool {
        let settings = QwengramSettings.shared
        return settings.qwengramEnabled && settings.hideStoryViews
    }

    public static var suppressOnlinePresence: Bool {
        let settings = QwengramSettings.shared
        return settings.qwengramEnabled && settings.hideOnlinePresence
    }
}
