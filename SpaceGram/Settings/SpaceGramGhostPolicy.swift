import Foundation

// No Telegram types or network effects: hooks consult the same effective policy.
public enum SpaceGramGhostPolicy {
    public static var suppressAutomaticReads: Bool {
        let settings = SpaceGramSettings.shared
        return settings.ghostMode.enabled
    }

    public static var suppressChatActivity: Bool {
        let settings = SpaceGramSettings.shared
        return settings.ghostMode.enabled
    }

    public static var suppressStoryViews: Bool {
        let settings = SpaceGramSettings.shared
        return settings.ghostMode.enabled
    }

    public static var suppressOnlinePresence: Bool {
        let settings = SpaceGramSettings.shared
        return settings.ghostMode.enabled
    }

    public static var shouldReadOnInteraction: Bool {
        let settings = SpaceGramSettings.shared
        return settings.ghostMode.enabled && settings.readOnInteract
    }
}
