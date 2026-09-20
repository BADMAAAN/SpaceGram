import TelegramCore
import XCTest

final class SpaceGramDelayedSendPostUploadTests: XCTestCase {
    func testSlowMediaUploadMovesScheduleBeyondFreshServerTime() {
        XCTAssertEqual(
            spaceGramAdjustedScheduleTime(plannedTime: 112, currentServerTime: 115, minimumDelay: 12),
            145
        )
    }

    func testScheduleAlreadyTooCloseGetsFullThreshold() {
        XCTAssertEqual(
            spaceGramAdjustedScheduleTime(plannedTime: 120, currentServerTime: 110, minimumDelay: 12),
            140
        )
    }

    func testScheduleInPastGetsFullThreshold() {
        XCTAssertEqual(
            spaceGramAdjustedScheduleTime(plannedTime: 100, currentServerTime: 120, minimumDelay: 12),
            150
        )
    }

    func testReconnectRevalidatesAgainstNewServerTime() {
        let firstAttempt = spaceGramAdjustedScheduleTime(plannedTime: 112, currentServerTime: 110, minimumDelay: 12)
        XCTAssertEqual(firstAttempt, 140)
        XCTAssertEqual(
            spaceGramAdjustedScheduleTime(plannedTime: firstAttempt, currentServerTime: 125, minimumDelay: 12),
            155
        )
    }

    func testNativeScheduleAndDuplicateSafeRetryRemainStable() {
        XCTAssertEqual(
            spaceGramAdjustedScheduleTime(plannedTime: 101, currentServerTime: 100, minimumDelay: nil),
            101
        )
        let first = spaceGramAdjustedScheduleTime(plannedTime: 112, currentServerTime: 115, minimumDelay: 12)
        let retry = spaceGramAdjustedScheduleTime(plannedTime: 112, currentServerTime: 115, minimumDelay: 12)
        XCTAssertEqual(first, retry)

        let attribute = OutgoingScheduleInfoMessageAttribute(scheduleTime: 112, repeatPeriod: nil, spaceGramMinimumDelay: 12)
        XCTAssertEqual(attribute.withUpdatedScheduleTime(127).spaceGramMinimumDelay, 12)
    }
}
