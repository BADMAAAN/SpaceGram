import Display
import UIKit
import XCTest

final class SpaceGramWindowBrandingTests: XCTestCase {
    func testRealWindowHostCannotRestoreDecorativeStatusBarBadge() {
        let done = expectation(description: "window lifecycle branding")
        DispatchQueue.main.async {
            let (nativeWindow, host) = nativeWindowHostView()
            let window = Window1(hostView: host, statusBarHost: nil)
            XCTAssertTrue(window.badgeView.superview === host.containerView)
            XCTAssertNil(window.badgeView.image)
            XCTAssertTrue(window.badgeView.isHidden)
            // Model a stale overlay image and the actual root visibility calls.
            for hidden in [false, true, false, true] {
                window.badgeView.image = UIImage(systemName: "circle.fill")
                window.setForceBadgeHidden(hidden)
                XCTAssertNil(window.badgeView.image)
                XCTAssertTrue(window.badgeView.isHidden)
                XCTAssertFalse(window.badgeView.isUserInteractionEnabled)
            }
            withExtendedLifetime(nativeWindow) { done.fulfill() }
        }
        wait(for: [done], timeout: 10)
    }
}
