import Foundation
import NagramSettings
import SpaceGramSettings
import SpaceGramSettingsSignal
import SwiftSignalKit
import XCTest

final class SpaceGramSettingsStartupTests: XCTestCase {
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
        let completed = expectation(description: "Presence policy bootstrap returns")
        DispatchQueue.global().async {
            let disposable = spaceGramSuppressOnlinePresenceSignal().start(next: { _ in })
            disposable.dispose()
            completed.fulfill()
        }
        wait(for: [completed], timeout: 5.0)
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
}
