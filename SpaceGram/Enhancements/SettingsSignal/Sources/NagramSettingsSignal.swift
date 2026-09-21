import Foundation
import NagramSettings
import SwiftSignalKit
import UIKit

// MARK: NAGRAM — 增强开关的响应式桥接。
// 用 UserDefaults.didChangeNotification 把开关变化转成 Signal，供需即时刷新的功能（如 hideStories）订阅。
// 独立模块：依赖 SwiftSignalKit，不污染纯 Foundation 的 NagramSettings 数据层。
private func nagramDefaultsSignal<Value: Equatable>(_ value: @escaping () -> Value) -> Signal<Value, NoError> {
    return Signal<Value, NoError> { subscriber in
        // Cloud bootstrap can write defaults; finish before observing them.
        _ = NagramSettings.shared
        let lock = NSRecursiveLock()
        var isDisposed = false
        let emit: () -> Void = {
            lock.lock()
            defer { lock.unlock() }
            guard !isDisposed else { return }
            subscriber.putNext(value())
        }

        lock.lock()
        let observer = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: NagramDemoMode.userDefaults,
            queue: nil
        ) { _ in
            emit()
        }
        emit()
        lock.unlock()

        return ActionDisposable {
            lock.lock()
            isDisposed = true
            lock.unlock()
            NotificationCenter.default.removeObserver(observer)
        }
    }
    |> distinctUntilChanged
}

public func nagramBoolSignal(_ key: String, defaultValue: Bool) -> Signal<Bool, NoError> {
    return nagramDefaultsSignal {
        NagramDemoMode.userDefaults.object(forKey: key) as? Bool ?? defaultValue
    }
}

public func nagramStringSignal(_ key: String, defaultValue: String) -> Signal<String, NoError> {
    return nagramDefaultsSignal {
        NagramDemoMode.userDefaults.string(forKey: key) ?? defaultValue
    }
}

public func nagramRecentStickerLimitSignal() -> Signal<Int, NoError> {
    return nagramDefaultsSignal {
        NagramSettings.shared.recentStickerLimitValue
    }
}

public func nagramAutoTranslateSignal(accountPeerId: Int64, peerId: Int64, threadId: Int64?) -> Signal<Bool, NoError> {
    return nagramBoolSignal(NagramSettings.autoTranslateKey(accountPeerId: accountPeerId, peerId: peerId, threadId: threadId), defaultValue: false)
}

public func nagramBottomBarSettingsSignal() -> Signal<NagramBottomBarSettings, NoError> {
    return nagramDefaultsSignal {
        NagramSettings.shared.bottomBarSettings
    }
}

public func nagramGlassTransparencySignal() -> Signal<Int32, NoError> {
    return Signal<Int32, NoError> { subscriber in
        let lock = NSRecursiveLock()
        var version: Int32 = 0
        var isDisposed = false
        let emit: () -> Void = {
            lock.lock()
            defer { lock.unlock() }
            guard !isDisposed else { return }
            version &+= 1
            subscriber.putNext(version)
        }

        lock.lock()
        let defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: NagramDemoMode.userDefaults,
            queue: nil
        ) { _ in
            emit()
        }
        let accessibilityObserver = NotificationCenter.default.addObserver(
            forName: UIAccessibility.reduceTransparencyStatusDidChangeNotification,
            object: nil,
            queue: nil
        ) { _ in
            emit()
        }
        subscriber.putNext(version)
        lock.unlock()

        return ActionDisposable {
            lock.lock()
            isDisposed = true
            lock.unlock()
            NotificationCenter.default.removeObserver(defaultsObserver)
            NotificationCenter.default.removeObserver(accessibilityObserver)
        }
    }
}

public func nagramRegexFiltersSignal() -> Signal<Int32, NoError> {
    return Signal<Int32, NoError> { subscriber in
        let lock = NSRecursiveLock()
        var version: Int32 = 0
        var isDisposed = false
        let emit: () -> Void = {
            lock.lock()
            defer { lock.unlock() }
            guard !isDisposed else { return }
            version &+= 1
            subscriber.putNext(version)
        }

        lock.lock()
        let observer = NotificationCenter.default.addObserver(
            forName: Notification.Name("NagramRegexFiltersDidChange"),
            object: nil,
            queue: nil
        ) { _ in
            emit()
        }
        subscriber.putNext(version)
        lock.unlock()

        return ActionDisposable {
            lock.lock()
            isDisposed = true
            lock.unlock()
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
