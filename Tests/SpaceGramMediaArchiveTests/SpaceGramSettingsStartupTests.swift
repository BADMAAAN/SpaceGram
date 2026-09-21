import Foundation
import NagramSettings
import NagramSettingsSignal
import SpaceGramSettings
import SpaceGramSettingsSignal
import SwiftSignalKit
import XCTest

final class SpaceGramSettingsStartupTests: XCTestCase {
    // Can also be selected alone in a fresh runner to cover first subscription.
    func testPersistedReadOnInteractOnAndOffSurvivePolicySubscription() {
        let defaults = UserDefaults.standard
        let keys = ["enabled", "ghostModeEnabled", "readOnInteract"].map { "spacegram.settings." + $0 }
        let previous = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, previous) {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        defaults.set(true, forKey: keys[0])
        defaults.set(true, forKey: keys[1])
        for persisted in [false, true] {
            defaults.set(persisted, forKey: keys[2])
            var emitted: Bool?
            let disposable = spaceGramSuppressAutomaticReadsSignal().start(next: { emitted = $0 })
            XCTAssertEqual(emitted, true)
            XCTAssertEqual(SpaceGramGhostPolicy.shouldReadOnInteraction, persisted)
            XCTAssertEqual(defaults.bool(forKey: keys[2]), persisted)
            disposable.dispose()
        }
    }

    func testSettingsWritesDoNotRecursivelyEnterPolicySubscriber() {
        _ = SpaceGramSettings.shared
        let enabledKey = "spacegram.settings.enabled"
        let key = "spacegram.settings.botsHubEnabled"
        let defaults = UserDefaults.standard
        let previousEnabled = defaults.object(forKey: enabledKey)
        let previous = defaults.object(forKey: key)
        defer {
            if let previousEnabled { defaults.set(previousEnabled, forKey: enabledKey) }
            else { defaults.removeObject(forKey: enabledKey) }
            if let previous { defaults.set(previous, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }
        defaults.set(true, forKey: enabledKey)
        defaults.set(false, forKey: key)
        let completed = expectation(description: "ON and OFF propagated")
        let lock = NSRecursiveLock()
        var values: [Bool] = []
        var depth = 0
        var maxDepth = 0
        let disposable = spaceGramToolsEnabledSignal().start(next: { value in
            lock.lock()
            defer { depth -= 1; lock.unlock() }
            depth += 1
            maxDepth = max(maxDepth, depth)
            values.append(value)
            if values.count < 3 {
                defaults.set(!value, forKey: key)
                NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: defaults)
            } else {
                completed.fulfill()
            }
        })
        wait(for: [completed], timeout: 5.0)
        disposable.dispose()
        lock.lock()
        XCTAssertEqual(values, [false, true, false])
        XCTAssertEqual(maxDepth, 1)
        lock.unlock()
    }

    func testOutOfRangeEnhancementPreferenceFallsBackWithoutTrapping() {
        let key = "SpaceGramTests." + UUID().uuidString
        let defaults = NagramDemoMode.userDefaults
        defer { defaults.removeObject(forKey: key) }
        let setting = NagramDefault<Int32>(key, 7)
        for value in [Int64.max, Int64.min] {
            defaults.set(value, forKey: key)
            XCTAssertEqual(setting.wrappedValue, 7)
        }
        defaults.set(42, forKey: key)
        XCTAssertEqual(setting.wrappedValue, 42)
    }

    // Run this test alone in a fresh test runner to exercise cold singleton
    // initialization, as well as in the full suite for subsequent subscriptions.
    func testColdPresenceSubscriptionCompletes() {
        let completed = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            let disposable = spaceGramSuppressOnlinePresenceSignal().start(next: { _ in })
            disposable.dispose()
            completed.signal()
        }
        XCTAssertEqual(completed.wait(timeout: .now() + 5.0), .success)
    }

    func testSettingsNotificationAllowsReentrantSubscriptionAndDisposal() {
        var emissions = 0
        let disposable = spaceGramEnabledSignal().start(next: { _ in
            emissions += 1
            let nested = spaceGramSuppressChatActivitySignal().start(next: { _ in })
            nested.dispose()
        })
        XCTAssertEqual(emissions, 1)
        // No production preference is modified. Duplicate notifications should
        // not re-emit unchanged values or deadlock nested policy subscriptions.
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: UserDefaults.standard)
        XCTAssertEqual(emissions, 1)
        disposable.dispose()
        NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: UserDefaults.standard)
        XCTAssertEqual(emissions, 1)
    }

    func testEnhancementSignalSerializesReentrantDefaultsNotification() {
        let key = "SpaceGramTests." + UUID().uuidString
        let defaults = NagramDemoMode.userDefaults
        defaults.set(false, forKey: key)
        defer { defaults.removeObject(forKey: key) }

        var values: [Bool] = []
        let disposable = nagramBoolSignal(key, defaultValue: false).start(next: { value in
            values.append(value)
            if !value {
                defaults.set(true, forKey: key)
                NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: defaults)
            }
        })
        disposable.dispose()
        XCTAssertEqual(values, [false, true])
    }
}
