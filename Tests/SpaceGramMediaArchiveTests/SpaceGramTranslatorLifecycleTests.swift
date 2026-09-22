import SpaceGramSettingsUI
import SwiftSignalKit
import XCTest

final class SpaceGramTranslatorLifecycleTests: XCTestCase {
    func testSuccessCompletesExactlyOnce() {
        let lifecycle = SpaceGramTranslatorRequestLifecycle()
        var disposeCount = 0
        let token = lifecycle.begin()
        lifecycle.setDisposable(ActionDisposable { disposeCount += 1 }, for: token)

        XCTAssertTrue(lifecycle.finish(token))
        XCTAssertFalse(lifecycle.finish(token))
        XCTAssertEqual(disposeCount, 1)
    }

    func testLateCompletionAfterBackIsIgnored() {
        let lifecycle = SpaceGramTranslatorRequestLifecycle()
        var disposeCount = 0
        let token = lifecycle.begin()
        lifecycle.setDisposable(ActionDisposable { disposeCount += 1 }, for: token)

        lifecycle.cancel()

        XCTAssertFalse(lifecycle.finish(token))
        XCTAssertEqual(disposeCount, 1)
    }

    func testRepeatedSessionRejectsPreviousCompletion() {
        let lifecycle = SpaceGramTranslatorRequestLifecycle()
        var firstDisposeCount = 0
        let first = lifecycle.begin()
        lifecycle.setDisposable(ActionDisposable { firstDisposeCount += 1 }, for: first)

        let second = lifecycle.begin()

        XCTAssertEqual(firstDisposeCount, 1)
        XCTAssertFalse(lifecycle.finish(first))
        XCTAssertTrue(lifecycle.finish(second))
    }

    func testCancelledInteractivePopLeavesOpenSessionActive() {
        let lifecycle = SpaceGramTranslatorRequestLifecycle()
        let token = lifecycle.begin()

        // A cancelled interactive pop never calls cancel because the controller
        // remains in its navigation stack.
        XCTAssertTrue(lifecycle.finish(token))
    }

    func testDeallocationCancelsRequest() {
        var disposeCount = 0
        weak var weakLifecycle: SpaceGramTranslatorRequestLifecycle?
        autoreleasepool {
            let lifecycle = SpaceGramTranslatorRequestLifecycle()
            weakLifecycle = lifecycle
            let token = lifecycle.begin()
            lifecycle.setDisposable(ActionDisposable { disposeCount += 1 }, for: token)
        }

        XCTAssertNil(weakLifecycle)
        XCTAssertEqual(disposeCount, 1)
    }
}
