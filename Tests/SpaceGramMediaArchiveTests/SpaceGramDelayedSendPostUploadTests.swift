import TelegramCore
import XCTest

final class SpaceGramDelayedSendPostUploadTests: XCTestCase {
    func testSlowMediaUploadMovesScheduleBeyondFreshServerTime() {
        XCTAssertEqual(
            spaceGramAdjustedScheduleTime(plannedTime: 112, currentServerTime: 115, minimumDelay: 12),
            127
        )
    }

    func testScheduleAlreadyTooCloseGetsFullThreshold() {
        XCTAssertEqual(
            spaceGramAdjustedScheduleTime(plannedTime: 120, currentServerTime: 110, minimumDelay: 12),
            122
        )
    }

    func testScheduleInPastGetsFullThreshold() {
        XCTAssertEqual(
            spaceGramAdjustedScheduleTime(plannedTime: 100, currentServerTime: 120, minimumDelay: 12),
            132
        )
    }

    func testReconnectRevalidatesAgainstNewServerTime() {
        let firstAttempt = spaceGramAdjustedScheduleTime(plannedTime: 112, currentServerTime: 110, minimumDelay: 12)
        XCTAssertEqual(firstAttempt, 122)
        XCTAssertEqual(
            spaceGramAdjustedScheduleTime(plannedTime: firstAttempt, currentServerTime: 125, minimumDelay: 12),
            137
        )
    }

    func testFractionalCorrectedServerClockAndExplicitFutureDate() {
        XCTAssertEqual(spaceGramAdjustedScheduleTime(plannedTime: 112, currentServerTime: 115.75, minimumDelay: 12), 128)
        XCTAssertEqual(spaceGramAdjustedScheduleTime(plannedTime: 1000, currentServerTime: 115, minimumDelay: nil), 1000)
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
