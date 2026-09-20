import SpaceGramMessageShot
import UIKit
import XCTest

final class SpaceGramMessageShotTests: XCTestCase {
    private let style = SpaceGramMessageShotStyle(
        backgroundColor: .black,
        incomingBubbleColor: .darkGray,
        outgoingBubbleColor: .systemBlue,
        incomingTextColor: .white,
        outgoingTextColor: .white,
        secondaryTextColor: .lightGray,
        accentColor: .systemCyan
    )

    private func item(_ text: String, media: SpaceGramMessageShotMedia? = nil) -> SpaceGramMessageShotItem {
        return SpaceGramMessageShotItem(outgoing: false, sender: "Test User", avatarInitials: "TU", timestamp: "12:34", text: NSAttributedString(string: text), replyPreview: nil, media: media)
    }

    func testOneTextMessageRenders() throws {
        let image = try SpaceGramMessageShotRenderer().render(items: [self.item("Hello")], style: self.style)
        XCTAssertGreaterThan(image.size.width, 0.0)
        XCTAssertGreaterThan(image.size.height, 0.0)
    }

    func testManyMessagesAreBounded() throws {
        let items = (0 ..< 100).map { self.item("Message \($0) " + String(repeating: "text ", count: 20)) }
        let options = SpaceGramMessageShotOptions(width: 390.0, maximumMessages: 20, maximumHeight: 1200.0, maximumPixelCount: 2_000_000.0)
        let layout = try SpaceGramMessageShotRenderer().layout(items: items, options: options)
        XCTAssertLessThanOrEqual(layout.renderedMessageCount, 20)
        XCTAssertGreaterThan(layout.omittedMessageCount, 0)
        XCTAssertLessThanOrEqual(layout.size.height, 1200.0)
        XCTAssertLessThanOrEqual(layout.size.width * layout.size.height * layout.scale * layout.scale, 2_000_001.0)
    }

    func testPhotoThumbnailRenders() throws {
        let thumbnail = UIGraphicsImageRenderer(size: CGSize(width: 20.0, height: 20.0)).image { context in
            UIColor.red.setFill()
            context.cgContext.fill(CGRect(x: 0.0, y: 0.0, width: 20.0, height: 20.0))
        }
        let media = SpaceGramMessageShotMedia(kind: .photo, title: "Photo", image: thumbnail)
        let image = try SpaceGramMessageShotRenderer().render(items: [self.item("Caption", media: media)], style: self.style)
        XCTAssertGreaterThan(image.size.height, 200.0)
    }

    func testUnsupportedMediaUsesPlaceholder() throws {
        let media = SpaceGramMessageShotMedia(kind: .unsupported, title: "Unsupported media", image: nil)
        XCTAssertNoThrow(try SpaceGramMessageShotRenderer().render(items: [self.item("", media: media)], style: self.style))
    }

    func testEmptySelectionFailsWithoutAllocatingBitmap() {
        XCTAssertThrowsError(try SpaceGramMessageShotRenderer().render(items: [], style: self.style)) { error in
            XCTAssertEqual(error as? SpaceGramMessageShotError, .emptySelection)
        }
    }
}
