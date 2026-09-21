import Foundation
import SpaceGramSettings
import SwiftSignalKit

private let settingsNotificationQueue = DispatchQueue(label: "SpaceGram.SettingsNotifications")

// Bootstrap first, then observe before reading the initial value so subsequent
// changes cannot be missed. Serialize reads/emissions from notification threads.
private func settingsSignal<T>(_ read: @escaping () -> T) -> Signal<T, NoError> {
    return Signal { subscriber in
        // Migration writes UserDefaults synchronously. Finish the singleton's
        // initialization before installing any observer that reads it again.
        // Otherwise the notification can re-enter Swift's once initialization.
        _ = SpaceGramSettings.shared
        let lock = NSRecursiveLock()
        var disposed = false
        let emit = {
            lock.lock()
            defer { lock.unlock() }
            guard !disposed else { return }
            subscriber.putNext(read())
        }
        let observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: nil
        ) { _ in
            // A subscriber may initialize enhancement settings (including iCloud
            // migration) or write defaults. Never re-enter that subscriber from
            // inside a defaults write or a Swift singleton's once initializer.
            settingsNotificationQueue.async { emit() }
        }
        emit()
        return ActionDisposable {
            lock.lock()
            disposed = true
            lock.unlock()
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

public func spaceGramHistorySettingsSignal() -> Signal<(Bool, Bool, Bool), NoError> {
    return settingsSignal {
        let settings = SpaceGramSettings.shared
        return (settings.messageHistoryEnabled, settings.saveEditedMessages, settings.saveServerDeletedMessages)
    }
    |> distinctUntilChanged(isEqual: { lhs, rhs in
        return lhs.0 == rhs.0 && lhs.1 == rhs.1 && lhs.2 == rhs.2
    })
}

public func spaceGramHistoryIndicatorSettingsSignal() -> Signal<(Bool, Bool, Bool), NoError> {
    return settingsSignal {
        let settings = SpaceGramSettings.shared
        return (settings.showHistoryIndicator, settings.showEditedIndicator, settings.showDeletedIndicator)
    }
    |> distinctUntilChanged(isEqual: { lhs, rhs in
        lhs.0 == rhs.0 && lhs.1 == rhs.1 && lhs.2 == rhs.2
    })
}

public func spaceGramEnabledSignal() -> Signal<Bool, NoError> {
    return settingsSignal { SpaceGramSettings.shared.spaceGramEnabled } |> distinctUntilChanged
}

/// Refresh a settings screen for any preference change, including retained
/// enhancement keys. Bootstrap/notification ordering stays in settingsSignal.
public func spaceGramSettingsChangesSignal() -> Signal<Int, NoError> {
    return settingsSignal { 0 }
}

public func botsHubEnabledSignal() -> Signal<Bool, NoError> {
    return settingsSignal { SpaceGramSettings.shared.botsHubEnabled } |> distinctUntilChanged
}

public func spaceGramToolsEnabledSignal() -> Signal<Bool, NoError> {
    return settingsSignal { SpaceGramSettings.shared.toolsEnabled } |> distinctUntilChanged
}

public func spaceGramGhostSettingsSignal() -> Signal<(Bool, Bool, Bool), NoError> {
    return settingsSignal {
        let settings = SpaceGramSettings.shared
        return (settings.hideChatActivity, settings.hideStoryViews, settings.hideOnlinePresence)
    }
    |> distinctUntilChanged(isEqual: { lhs, rhs in
        return lhs.0 == rhs.0 && lhs.1 == rhs.1 && lhs.2 == rhs.2
    })
}

public func spaceGramSuppressOnlinePresenceSignal() -> Signal<Bool, NoError> {
    return settingsSignal { SpaceGramGhostPolicy.suppressOnlinePresence } |> distinctUntilChanged
}

public func spaceGramGoOfflineAutomaticallySignal() -> Signal<Bool, NoError> {
    return settingsSignal {
        let settings = SpaceGramSettings.shared
        return SpaceGramGhostPolicy.suppressOnlinePresence && settings.goOfflineAutomatically
    }
    |> distinctUntilChanged
}

public func spaceGramSuppressChatActivitySignal() -> Signal<Bool, NoError> {
    return settingsSignal { SpaceGramGhostPolicy.suppressChatActivity } |> distinctUntilChanged
}

public func spaceGramAutomaticReadsSettingSignal() -> Signal<Bool, NoError> {
    return settingsSignal { SpaceGramSettings.shared.suppressAutomaticReads } |> distinctUntilChanged
}

public func spaceGramSuppressAutomaticReadsSignal() -> Signal<Bool, NoError> {
    return settingsSignal { SpaceGramGhostPolicy.suppressAutomaticReads } |> distinctUntilChanged
}

public func spaceGramMediaArchiveSettingSignal() -> Signal<Bool, NoError> {
    return settingsSignal { SpaceGramSettings.shared.mediaArchiveEnabled } |> distinctUntilChanged
}
