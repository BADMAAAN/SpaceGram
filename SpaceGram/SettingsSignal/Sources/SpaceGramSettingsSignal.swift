import Foundation
import SpaceGramSettings
import SwiftSignalKit

// Bootstrap first, then observe before reading the initial value so subsequent
// changes cannot be missed. Subscriber callbacks always run outside the lock.
private func settingsSignal<T>(read: @escaping () -> T, isEqual: @escaping (T, T) -> Bool) -> Signal<T, NoError> {
    return Signal { subscriber in
        // Migration writes UserDefaults synchronously. Finish the singleton's
        // initialization before installing any observer that reads it again.
        // Otherwise the notification can re-enter Swift's once initialization.
        _ = SpaceGramSettings.shared
        let lock = NSLock()
        var disposed = false
        var isDelivering = false
        var notificationPending = false
        var hasCurrentValue = false
        var currentValue: T?

        let deliver: () -> Void = {
            lock.lock()
            if disposed {
                lock.unlock()
                return
            }
            if isDelivering {
                notificationPending = true
                lock.unlock()
                return
            }
            isDelivering = true
            lock.unlock()

            while true {
                lock.lock()
                notificationPending = false
                let shouldRead = !disposed
                lock.unlock()
                guard shouldRead else { return }

                let value = read()
                lock.lock()
                if disposed {
                    isDelivering = false
                    notificationPending = false
                    lock.unlock()
                    return
                }
                let shouldEmit = !hasCurrentValue || currentValue.map { !isEqual($0, value) } == true
                if shouldEmit {
                    currentValue = value
                    hasCurrentValue = true
                }
                lock.unlock()

                if shouldEmit {
                    subscriber.putNext(value)
                }

                lock.lock()
                if disposed {
                    isDelivering = false
                    notificationPending = false
                    lock.unlock()
                    return
                } else if notificationPending {
                    lock.unlock()
                    continue
                } else {
                    isDelivering = false
                    lock.unlock()
                    return
                }
            }
        }
        let observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: nil
        ) { _ in
            // A write from inside a subscriber is queued for the current delivery
            // loop. It is neither delivered recursively nor dropped.
            deliver()
        }
        deliver()
        return ActionDisposable {
            lock.lock()
            disposed = true
            notificationPending = false
            lock.unlock()
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

private func settingsSignal<T: Equatable>(read: @escaping () -> T) -> Signal<T, NoError> {
    return settingsSignal(read: read, isEqual: ==)
}

public func spaceGramHistorySettingsSignal() -> Signal<(Bool, Bool, Bool), NoError> {
    return settingsSignal(read: {
        let settings = SpaceGramSettings.shared
        return (settings.messageHistoryEnabled, settings.saveEditedMessages, settings.saveServerDeletedMessages)
    }, isEqual: { lhs, rhs in
        return lhs.0 == rhs.0 && lhs.1 == rhs.1 && lhs.2 == rhs.2
    })
}

public func spaceGramHistoryIndicatorSettingsSignal() -> Signal<(Bool, Bool, Bool), NoError> {
    return settingsSignal(read: {
        let settings = SpaceGramSettings.shared
        return (settings.showHistoryIndicator, settings.showEditedIndicator, settings.showDeletedIndicator)
    }, isEqual: { lhs, rhs in
        lhs.0 == rhs.0 && lhs.1 == rhs.1 && lhs.2 == rhs.2
    })
}

public func spaceGramEnabledSignal() -> Signal<Bool, NoError> {
    return settingsSignal(read: { SpaceGramSettings.shared.spaceGramEnabled })
}

/// Refresh a settings screen for any preference change, including retained
/// enhancement keys. Bootstrap/notification ordering stays in settingsSignal.
public func spaceGramSettingsChangesSignal() -> Signal<Int, NoError> {
    return settingsSignal(read: { 0 }, isEqual: { _, _ in false })
}

public func botsHubEnabledSignal() -> Signal<Bool, NoError> {
    return settingsSignal(read: { SpaceGramSettings.shared.botsHubEnabled })
}

public func spaceGramToolsEnabledSignal() -> Signal<Bool, NoError> {
    return settingsSignal(read: { SpaceGramSettings.shared.toolsEnabled })
}

public func spaceGramGhostSettingsSignal() -> Signal<(Bool, Bool, Bool), NoError> {
    return settingsSignal(read: {
        let settings = SpaceGramSettings.shared
        return (settings.hideChatActivity, settings.hideStoryViews, settings.hideOnlinePresence)
    }, isEqual: { lhs, rhs in
        return lhs.0 == rhs.0 && lhs.1 == rhs.1 && lhs.2 == rhs.2
    })
}

public func spaceGramSuppressOnlinePresenceSignal() -> Signal<Bool, NoError> {
    return settingsSignal(read: { SpaceGramGhostPolicy.suppressOnlinePresence })
}

public func spaceGramGoOfflineAutomaticallySignal() -> Signal<Bool, NoError> {
    return settingsSignal(read: {
        let settings = SpaceGramSettings.shared
        return SpaceGramGhostPolicy.suppressOnlinePresence && settings.goOfflineAutomatically
    })
}

public func spaceGramSuppressChatActivitySignal() -> Signal<Bool, NoError> {
    return settingsSignal(read: { SpaceGramGhostPolicy.suppressChatActivity })
}

public func spaceGramAutomaticReadsSettingSignal() -> Signal<Bool, NoError> {
    return settingsSignal(read: { SpaceGramSettings.shared.suppressAutomaticReads })
}

public func spaceGramSuppressAutomaticReadsSignal() -> Signal<Bool, NoError> {
    return settingsSignal(read: { SpaceGramGhostPolicy.suppressAutomaticReads })
}

public func spaceGramMediaArchiveSettingSignal() -> Signal<Bool, NoError> {
    return settingsSignal(read: { SpaceGramSettings.shared.mediaArchiveEnabled })
}
