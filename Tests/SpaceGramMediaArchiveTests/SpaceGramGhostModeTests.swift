import Foundation
import SpaceGramSettings
import XCTest

final class SpaceGramGhostModeTests: XCTestCase {
    private let full = SpaceGramGhostMode(enabled: true, reads: true, stories: true, presence: true, activity: true)

    func testPersistentMasterProtectsEveryPathDespiteLegacyPartialSettings() {
        let settings = SpaceGramSettings.shared
        let defaults = UserDefaults.standard
        let keys = ["enabled", "ghostModeEnabled", "suppressAutomaticReads", "hideChatActivity", "hideStoryViews", "hideOnlinePresence", "readOnInteract"].map { "spacegram.settings." + $0 }
        let previous = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, previous) {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        settings.spaceGramEnabled = true
        settings.suppressAutomaticReads = false
        settings.hideChatActivity = false
        settings.hideStoryViews = false
        settings.hideOnlinePresence = false
        settings.readOnInteract = false
        settings.setGhostMode(true)
        XCTAssertTrue(defaults.bool(forKey: "spacegram.settings.ghostModeEnabled"))
        XCTAssertTrue(settings.ghostMode.isFull)
        XCTAssertTrue(SpaceGramGhostPolicy.suppressAutomaticReads)
        XCTAssertTrue(SpaceGramGhostPolicy.suppressChatActivity)
        XCTAssertTrue(SpaceGramGhostPolicy.suppressStoryViews)
        XCTAssertTrue(SpaceGramGhostPolicy.suppressOnlinePresence)
        XCTAssertFalse(SpaceGramGhostPolicy.shouldReadOnInteraction)
        settings.readOnInteract = true
        XCTAssertTrue(SpaceGramGhostPolicy.shouldReadOnInteraction)
        XCTAssertTrue(SpaceGramGhostPolicy.suppressAutomaticReads)
        settings.setGhostMode(false)
        XCTAssertFalse(SpaceGramGhostPolicy.suppressAutomaticReads)
        XCTAssertFalse(SpaceGramGhostPolicy.suppressChatActivity)
        XCTAssertFalse(SpaceGramGhostPolicy.suppressStoryViews)
        XCTAssertFalse(SpaceGramGhostPolicy.suppressOnlinePresence)
        XCTAssertFalse(SpaceGramGhostPolicy.shouldReadOnInteraction)
    }

    func testFullGhostRequiresEveryControlAndMaster() {
        XCTAssertTrue(full.isFull)
        XCTAssertFalse(SpaceGramGhostMode(enabled: false, reads: true, stories: true, presence: true, activity: true).isFull)
        XCTAssertFalse(SpaceGramGhostMode(enabled: true, reads: false, stories: true, presence: true, activity: true).isFull)
        XCTAssertFalse(SpaceGramGhostMode(enabled: true, reads: true, stories: false, presence: true, activity: true).isFull)
        XCTAssertFalse(SpaceGramGhostMode(enabled: true, reads: true, stories: true, presence: false, activity: true).isFull)
        XCTAssertFalse(SpaceGramGhostMode(enabled: true, reads: true, stories: true, presence: true, activity: false).isFull)
    }

    func testTextDelayAndOptIn() {
        XCTAssertEqual(SpaceGramDelayedSendPolicy.delay(mediaBytes: nil), 12)
        XCTAssertEqual(SpaceGramDelayedSendPolicy.timestamp(now: 100, ghost: full, enabled: true, mediaBytes: nil), 112)
        XCTAssertNil(SpaceGramDelayedSendPolicy.timestamp(now: 100, ghost: full, enabled: false, mediaBytes: nil))
        let partial = SpaceGramGhostMode(enabled: true, reads: true, stories: true, presence: false, activity: true)
        XCTAssertEqual(SpaceGramDelayedSendPolicy.timestamp(now: 100, ghost: partial, enabled: true, mediaBytes: nil), 112)
        XCTAssertNil(SpaceGramDelayedSendPolicy.timestamp(now: 100, ghost: SpaceGramGhostMode(enabled: false, reads: true, stories: true, presence: true, activity: true), enabled: true, mediaBytes: nil))
    }

    func testUploadSizeDoesNotAddAnExtraDelay() {
        XCTAssertEqual(SpaceGramDelayedSendPolicy.delay(mediaBytes: 0), 12)
        XCTAssertEqual(SpaceGramDelayedSendPolicy.delay(mediaBytes: 1_048_576), 12)
        XCTAssertEqual(SpaceGramDelayedSendPolicy.delay(mediaBytes: 2_097_152), 12)
        XCTAssertEqual(SpaceGramDelayedSendPolicy.delay(mediaBytes: 3_145_728), 12)
        XCTAssertEqual(SpaceGramDelayedSendPolicy.delay(mediaBytes: 10_485_760), 12)
    }

    func testMalformedMetadataAndTimestampCannotTrap() {
        XCTAssertEqual(SpaceGramDelayedSendPolicy.delay(mediaBytes: -1), 12)
        XCTAssertEqual(SpaceGramDelayedSendPolicy.delay(mediaBytes: Int64.max), 12)
        XCTAssertNil(SpaceGramDelayedSendPolicy.timestamp(now: Int64.max, ghost: full, enabled: true, mediaBytes: nil))
        XCTAssertNil(SpaceGramDelayedSendPolicy.timestamp(now: Int64(Int32.max), ghost: full, enabled: true, mediaBytes: nil))
        XCTAssertNil(SpaceGramDelayedSendPolicy.timestamp(now: -1, ghost: full, enabled: true, mediaBytes: nil))
    }
}
