import Foundation
import QwengramSettings
import SwiftSignalKit

// Register before reading so a change cannot fall between the initial value and
// subscription. Serialize reads and emissions from arbitrary notification threads.
private func settingsSignal<T>(_ read: @escaping () -> T) -> Signal<T, NoError> {
    return Signal { subscriber in
        let lock = NSRecursiveLock()
        let emit = {
            lock.lock()
            defer { lock.unlock() }
            subscriber.putNext(read())
        }
        let observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: nil
        ) { _ in
            emit()
        }
        emit()
        return ActionDisposable {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

public func qwengramHistorySettingsSignal() -> Signal<(Bool, Bool, Bool), NoError> {
    return settingsSignal {
        let settings = QwengramSettings.shared
        return (settings.messageHistoryEnabled, settings.saveEditedMessages, settings.saveServerDeletedMessages)
    }
    |> distinctUntilChanged(isEqual: { lhs, rhs in
        return lhs.0 == rhs.0 && lhs.1 == rhs.1 && lhs.2 == rhs.2
    })
}

public func qwengramHistoryIndicatorSettingsSignal() -> Signal<(Bool, Bool, Bool), NoError> {
    return settingsSignal {
        let settings = QwengramSettings.shared
        return (settings.showHistoryIndicator, settings.showEditedIndicator, settings.showDeletedIndicator)
    }
    |> distinctUntilChanged(isEqual: { lhs, rhs in
        lhs.0 == rhs.0 && lhs.1 == rhs.1 && lhs.2 == rhs.2
    })
}

public func qwengramEnabledSignal() -> Signal<Bool, NoError> {
    return settingsSignal { QwengramSettings.shared.qwengramEnabled } |> distinctUntilChanged
}

public func botsHubEnabledSignal() -> Signal<Bool, NoError> {
    return settingsSignal { QwengramSettings.shared.botsHubEnabled } |> distinctUntilChanged
}

public func qwengramToolsEnabledSignal() -> Signal<Bool, NoError> {
    return settingsSignal { QwengramSettings.shared.toolsEnabled } |> distinctUntilChanged
}

public func qwengramGhostSettingsSignal() -> Signal<(Bool, Bool, Bool), NoError> {
    return settingsSignal {
        let settings = QwengramSettings.shared
        return (settings.hideChatActivity, settings.hideStoryViews, settings.hideOnlinePresence)
    }
    |> distinctUntilChanged(isEqual: { lhs, rhs in
        return lhs.0 == rhs.0 && lhs.1 == rhs.1 && lhs.2 == rhs.2
    })
}

public func qwengramSuppressOnlinePresenceSignal() -> Signal<Bool, NoError> {
    return settingsSignal { QwengramGhostPolicy.suppressOnlinePresence } |> distinctUntilChanged
}

public func qwengramSuppressChatActivitySignal() -> Signal<Bool, NoError> {
    return settingsSignal { QwengramGhostPolicy.suppressChatActivity } |> distinctUntilChanged
}

public func qwengramAutomaticReadsSettingSignal() -> Signal<Bool, NoError> {
    return settingsSignal { QwengramSettings.shared.suppressAutomaticReads } |> distinctUntilChanged
}

public func qwengramSuppressAutomaticReadsSignal() -> Signal<Bool, NoError> {
    return settingsSignal { QwengramGhostPolicy.suppressAutomaticReads } |> distinctUntilChanged
}

public func qwengramMediaArchiveSettingSignal() -> Signal<Bool, NoError> {
    return settingsSignal { QwengramSettings.shared.mediaArchiveEnabled } |> distinctUntilChanged
}
