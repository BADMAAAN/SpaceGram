import Foundation
import SpaceGramSettings
import XCTest

final class SpaceGramGhostModeTests: XCTestCase {
    private let full = SpaceGramGhostMode(enabled: true, reads: true, stories: true, presence: true, activity: true)

    func testFullGhostRequiresEveryControlAndMaster() {
        XCTAssertTrue(full.isFull)
        XCTAssertFalse(SpaceGramGhostMode(enabled: false, reads: true, stories: true, presence: true, activity: true).isFull)
        XCTAssertFalse(SpaceGramGhostMode(enabled: true, reads: false, stories: true, presence: true, activity: true).isFull)
        XCTAssertFalse(SpaceGramGhostMode(enabled: true, reads: true, stories: false, presence: true, activity: true).isFull)
        XCTAssertFalse(SpaceGramGhostMode(enabled: true, reads: true, stories: true, presence: false, activity: true).isFull)
        XCTAssertFalse(SpaceGramGhostMode(enabled: true, reads: true, stories: true, presence: true, activity: false).isFull)
    }

    func testTextDelayAndOptIn() {
        XCTAssertEqual(SpaceGramDelayedSendPolicy.delay(mediaBytes: nil), 30)
        XCTAssertEqual(SpaceGramDelayedSendPolicy.timestamp(now: 100, ghost: full, enabled: true, mediaBytes: nil), 130)
        XCTAssertNil(SpaceGramDelayedSendPolicy.timestamp(now: 100, ghost: full, enabled: false, mediaBytes: nil))
        let partial = SpaceGramGhostMode(enabled: true, reads: true, stories: true, presence: false, activity: true)
        XCTAssertEqual(SpaceGramDelayedSendPolicy.timestamp(now: 100, ghost: partial, enabled: true, mediaBytes: nil), 130)
        XCTAssertNil(SpaceGramDelayedSendPolicy.timestamp(now: 100, ghost: SpaceGramGhostMode(enabled: false, reads: true, stories: true, presence: true, activity: true), enabled: true, mediaBytes: nil))
    }

    func testUploadSizeDoesNotAddAnExtraDelay() {
        XCTAssertEqual(SpaceGramDelayedSendPolicy.delay(mediaBytes: 0), 30)
        XCTAssertEqual(SpaceGramDelayedSendPolicy.delay(mediaBytes: 1_048_576), 30)
        XCTAssertEqual(SpaceGramDelayedSendPolicy.delay(mediaBytes: 2_097_152), 30)
        XCTAssertEqual(SpaceGramDelayedSendPolicy.delay(mediaBytes: 3_145_728), 30)
        XCTAssertEqual(SpaceGramDelayedSendPolicy.delay(mediaBytes: 10_485_760), 30)
    }

    func testMalformedMetadataAndTimestampCannotTrap() {
        XCTAssertEqual(SpaceGramDelayedSendPolicy.delay(mediaBytes: -1), 30)
        XCTAssertEqual(SpaceGramDelayedSendPolicy.delay(mediaBytes: Int64.max), 30)
        XCTAssertNil(SpaceGramDelayedSendPolicy.timestamp(now: Int64.max, ghost: full, enabled: true, mediaBytes: nil))
        XCTAssertNil(SpaceGramDelayedSendPolicy.timestamp(now: Int64(Int32.max), ghost: full, enabled: true, mediaBytes: nil))
        XCTAssertNil(SpaceGramDelayedSendPolicy.timestamp(now: -1, ghost: full, enabled: true, mediaBytes: nil))
    }
}
