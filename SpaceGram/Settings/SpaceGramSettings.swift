import Foundation
import SpaceGramMigration

@propertyWrapper
public struct SpaceGramDefault {
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
public struct SpaceGramStringDefault {
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

public final class SpaceGramSettings {
    public static let shared = SpaceGramSettings()

    private init() {
        #if DEBUG
        NSLog("SpaceGramStartup: settings bootstrap begin")
        #endif
        if !SpaceGramMigrationCoordinator.migrateDefaults(UserDefaults.standard) {
            NSLog("SpaceGram: settings migration incomplete; legacy preferences retained")
        }
        self.publishEnabledForExtensions()
        #if DEBUG
        NSLog("SpaceGramStartup: settings bootstrap complete")
        #endif
    }

    @SpaceGramDefault("spacegram.settings.enabled", true)
    private var enabledValue: Bool

    public var spaceGramEnabled: Bool {
        get {
            if Bundle.main.object(forInfoDictionaryKey: "NSExtension") != nil,
               let bundleId = Bundle.main.bundleIdentifier,
               let separator = bundleId.range(of: ".", options: .backwards) {
                // Same suffix convention as NotificationService: <app>.<extension>.
                let baseId = String(bundleId[..<separator.lowerBound])
                return Self.enabledForExtensions(defaults: UserDefaults(suiteName: "group." + baseId))
            }
            return enabledValue
        }
        set {
            enabledValue = newValue
            publishEnabledForExtensions()
        }
    }

    public static func enabledForExtensions(defaults: UserDefaults?) -> Bool {
        return (defaults?.object(forKey: "spacegram.settings.enabled") as? Bool) ?? true
    }

    private func publishEnabledForExtensions() {
        // Only the main app owns the master switch. Extensions must not replace
        // the mirror with values from their separate standard defaults domain.
        guard Bundle.main.object(forInfoDictionaryKey: "NSExtension") == nil,
              let bundleId = Bundle.main.bundleIdentifier else { return }
        UserDefaults(suiteName: "group." + bundleId)?.set(enabledValue, forKey: "spacegram.settings.enabled")
    }

    @SpaceGramDefault("spacegram.settings.botsHubEnabled", true)
    public var botsHubEnabled: Bool

    @SpaceGramDefault("spacegram.settings.messageHistoryEnabled", true)
    public var messageHistoryEnabled: Bool

    @SpaceGramDefault("spacegram.settings.saveEditedMessages", true)
    public var saveEditedMessages: Bool

    @SpaceGramDefault("spacegram.settings.saveServerDeletedMessages", true)
    public var saveServerDeletedMessages: Bool

    @SpaceGramStringDefault("spacegram.settings.qwenModel", "qwen-plus")
    public var qwenModel: String

    @SpaceGramStringDefault("spacegram.settings.aiContextCharacters", "24000")
    private var aiContextCharactersValue: String

    public static let aiContextPresets = [8000, 16000, 24000]

    public var aiContextCharacters: Int {
        get {
            let value = Int(aiContextCharactersValue) ?? 24000
            return Self.aiContextPresets.contains(value) ? value : 24000
        }
        set {
            guard Self.aiContextPresets.contains(newValue) else { return }
            aiContextCharactersValue = String(newValue)
        }
    }

    @SpaceGramDefault("spacegram.settings.hideChatActivity", false)
    public var hideChatActivity: Bool

    @SpaceGramDefault("spacegram.settings.suppressAutomaticReads", false)
    public var suppressAutomaticReads: Bool

    @SpaceGramDefault("spacegram.settings.hideStoryViews", false)
    public var hideStoryViews: Bool

    @SpaceGramDefault("spacegram.settings.hideOnlinePresence", false)
    public var hideOnlinePresence: Bool

    public var ghostMode: SpaceGramGhostMode {
        return SpaceGramGhostMode(enabled: spaceGramEnabled, reads: suppressAutomaticReads, stories: hideStoryViews, presence: hideOnlinePresence, activity: hideChatActivity)
    }

    public func setGhostMode(_ enabled: Bool) {
        // Explicit user action only. Initialization never replaces legacy values.
        suppressAutomaticReads = enabled
        hideStoryViews = enabled
        hideOnlinePresence = enabled
        hideChatActivity = enabled
    }

    @SpaceGramDefault("spacegram.settings.delayedSend", false)
    public var delayedSend: Bool

    @SpaceGramDefault("spacegram.settings.showGhostButton", false)
    public var showGhostButton: Bool

    @SpaceGramDefault("spacegram.settings.mediaArchiveEnabled", false)
    public var mediaArchiveEnabled: Bool

    @SpaceGramDefault("spacegram.settings.showHistoryIndicator", true)
    public var showHistoryIndicator: Bool

    @SpaceGramDefault("spacegram.settings.showEditedIndicator", true)
    public var showEditedIndicator: Bool

    @SpaceGramDefault("spacegram.settings.showDeletedIndicator", true)
    public var showDeletedIndicator: Bool

    public var captureMedia: Bool {
        return spaceGramEnabled && messageHistoryEnabled && mediaArchiveEnabled
    }

    public var toolsEnabled: Bool {
        return spaceGramEnabled && botsHubEnabled
    }

    public var captureEditedMessages: Bool {
        return spaceGramEnabled && messageHistoryEnabled && saveEditedMessages
    }

    public var captureDeletedMessages: Bool {
        return spaceGramEnabled && messageHistoryEnabled && saveServerDeletedMessages
    }
}
