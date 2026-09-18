import Foundation

@propertyWrapper
public struct QwengramDefault {
    private let key: String
    private let defaultValue: Bool

    public init(_ key: String, _ defaultValue: Bool) {
        self.key = key
        self.defaultValue = defaultValue
    }

    public var wrappedValue: Bool {
        get {
            let defaults = UserDefaults.standard
            guard defaults.object(forKey: key) != nil else {
                return defaultValue
            }
            return defaults.bool(forKey: key)
        }
        nonmutating set {
            UserDefaults.standard.set(newValue, forKey: key)
        }
    }
}

@propertyWrapper
public struct QwengramStringDefault {
    private let key: String
    private let defaultValue: String

    public init(_ key: String, _ defaultValue: String) {
        self.key = key
        self.defaultValue = defaultValue
    }

    public var wrappedValue: String {
        get {
            UserDefaults.standard.string(forKey: key) ?? defaultValue
        }
        nonmutating set {
            UserDefaults.standard.set(newValue, forKey: key)
        }
    }
}

public final class QwengramSettings {
    public static let shared = QwengramSettings()

    private init() {
    }

    @QwengramDefault("qwengram.settings.enabled", true)
    public var qwengramEnabled: Bool

    @QwengramDefault("qwengram.settings.botsHubEnabled", true)
    public var botsHubEnabled: Bool

    @QwengramDefault("qwengram.settings.messageHistoryEnabled", true)
    public var messageHistoryEnabled: Bool

    @QwengramDefault("qwengram.settings.saveEditedMessages", true)
    public var saveEditedMessages: Bool

    @QwengramDefault("qwengram.settings.saveServerDeletedMessages", true)
    public var saveServerDeletedMessages: Bool

    @QwengramStringDefault("qwengram.settings.qwenModel", "qwen-plus")
    public var qwenModel: String

    @QwengramDefault("qwengram.settings.hideChatActivity", false)
    public var hideChatActivity: Bool

    @QwengramDefault("qwengram.settings.suppressAutomaticReads", false)
    public var suppressAutomaticReads: Bool

    @QwengramDefault("qwengram.settings.hideStoryViews", false)
    public var hideStoryViews: Bool

    @QwengramDefault("qwengram.settings.hideOnlinePresence", false)
    public var hideOnlinePresence: Bool

    @QwengramDefault("qwengram.settings.mediaArchiveEnabled", false)
    public var mediaArchiveEnabled: Bool

    public var captureMedia: Bool {
        return qwengramEnabled && messageHistoryEnabled && mediaArchiveEnabled
    }

    public var toolsEnabled: Bool {
        return qwengramEnabled && botsHubEnabled
    }

    public var captureEditedMessages: Bool {
        return qwengramEnabled && messageHistoryEnabled && saveEditedMessages
    }

    public var captureDeletedMessages: Bool {
        return qwengramEnabled && messageHistoryEnabled && saveServerDeletedMessages
    }
}
