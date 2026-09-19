import CoreGraphics
import Foundation
import ImageIO
import QwengramPrivacy
import XCTest

final class QwengramPrivacyTests: XCTestCase {
    func testNotificationPrivacyDefaultsPreserveContent() {
        let result = QwengramPrivacyPolicy.default.notificationPresentation(title: "Alice", subtitle: "Family", body: "Hello", appLocked: false)
        XCTAssertEqual(result.title, "Alice")
        XCTAssertEqual(result.subtitle, "Family")
        XCTAssertEqual(result.body, "Hello")
        XCTAssertTrue(result.allowsRichBody)
        XCTAssertTrue(result.allowsSender)
        XCTAssertTrue(result.allowsAttachments)
    }

    func testNotificationPrivacyCanApplyOnlyWhileAppIsLocked() {
        var policy = QwengramPrivacyPolicy(hideNotificationPreview: true, notificationPrivacyWhenAppLocked: true)
        XCTAssertEqual(policy.notificationPresentation(title: "Alice", subtitle: nil, body: "Secret", appLocked: false).body, "Secret")
        XCTAssertEqual(policy.notificationPresentation(title: "Alice", subtitle: nil, body: "Secret", appLocked: true).body, "New message")

        policy.useGenericNotificationText = true
        let result = policy.notificationPresentation(title: "Alice", subtitle: "Family", body: "Secret", appLocked: true)
        XCTAssertEqual(result.title, "Qwengram")
        XCTAssertNil(result.subtitle)
        XCTAssertEqual(result.body, "New notification")
        XCTAssertFalse(result.allowsSender)
        XCTAssertFalse(result.allowsAttachments)
    }

    func testAccountPoliciesRemainIsolated() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let first = root.appendingPathComponent("first", isDirectory: true)
        let second = root.appendingPathComponent("second", isDirectory: true)
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let firstMediaBox = first.appendingPathComponent("mediabox").path
        let secondMediaBox = second.appendingPathComponent("mediabox").path
        XCTAssertTrue(QwengramPrivacyPolicyStore.saveAccountPolicy(QwengramPrivacyPolicy(hideNotificationSender: true), accountId: 1, mediaBoxPath: firstMediaBox, baseBundleId: nil))
        XCTAssertTrue(QwengramPrivacyPolicyStore.saveAccountPolicy(QwengramPrivacyPolicy(stripPhotoMetadata: true), accountId: 2, mediaBoxPath: secondMediaBox, baseBundleId: nil))
        XCTAssertTrue(QwengramPrivacyPolicyStore.loadAccountPolicy(mediaBoxPath: firstMediaBox).hideNotificationSender)
        XCTAssertFalse(QwengramPrivacyPolicyStore.loadAccountPolicy(mediaBoxPath: firstMediaBox).stripPhotoMetadata)
        XCTAssertTrue(QwengramPrivacyPolicyStore.loadAccountPolicy(mediaBoxPath: secondMediaBox).stripPhotoMetadata)

        QwengramPrivacyPolicyStore.clearAccountPolicy(accountId: 1, mediaBoxPath: firstMediaBox, baseBundleId: nil)
        XCTAssertEqual(QwengramPrivacyPolicyStore.loadAccountPolicy(mediaBoxPath: firstMediaBox), .default)
        XCTAssertTrue(QwengramPrivacyPolicyStore.loadAccountPolicy(mediaBoxPath: secondMediaBox).stripPhotoMetadata)
    }

    func testStillImageSanitizerRemovesGPSAndExif() throws {
        let pixels = Data([255, 0, 0, 255])
        guard let provider = CGDataProvider(data: pixels as CFData),
              let image = CGImage(width: 1, height: 1, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            return XCTFail("Unable to create test image")
        }
        let encoded = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(encoded, "public.jpeg" as CFString, 1, nil) else {
            return XCTFail("Unable to create image destination")
        }
        let metadata: [CFString: Any] = [
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 12.34, kCGImagePropertyGPSLongitude: 56.78],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "private"]
        ]
        CGImageDestinationAddImage(destination, image, metadata as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        guard let originalSource = CGImageSourceCreateWithData(encoded as CFData, nil),
              let originalProperties = CGImageSourceCopyPropertiesAtIndex(originalSource, 0, nil) as? [CFString: Any] else {
            return XCTFail("Unable to inspect test image")
        }
        XCTAssertNotNil(originalProperties[kCGImagePropertyGPSDictionary])
        XCTAssertNotNil(originalProperties[kCGImagePropertyExifDictionary])

        guard let sanitized = QwengramMetadataSanitizer.sanitizeStillImage(encoded as Data),
              let source = CGImageSourceCreateWithData(sanitized as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return XCTFail("Unable to sanitize test image")
        }
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
        XCTAssertNil(properties[kCGImagePropertyExifDictionary])
    }
}
