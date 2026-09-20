import CoreGraphics
import Foundation
import ImageIO
import SpaceGramPrivacy
import XCTest

final class SpaceGramPrivacyTests: XCTestCase {
    func testNotificationPrivacyDefaultsPreserveContent() {
        let result = SpaceGramPrivacyPolicy.default.notificationPresentation(title: "Alice", subtitle: "Family", body: "Hello", appLocked: false)
        XCTAssertEqual(result.title, "Alice")
        XCTAssertEqual(result.subtitle, "Family")
        XCTAssertEqual(result.body, "Hello")
        XCTAssertTrue(result.allowsRichBody)
        XCTAssertTrue(result.allowsSender)
        XCTAssertTrue(result.allowsAttachments)
    }

    func testNotificationPrivacyCanApplyOnlyWhileAppIsLocked() {
        var policy = SpaceGramPrivacyPolicy(hideNotificationPreview: true, notificationPrivacyWhenAppLocked: true)
        XCTAssertEqual(policy.notificationPresentation(title: "Alice", subtitle: nil, body: "Secret", appLocked: false).body, "Secret")
        XCTAssertEqual(policy.notificationPresentation(title: "Alice", subtitle: nil, body: "Secret", appLocked: true).body, "New message")

        policy.useGenericNotificationText = true
        let result = policy.notificationPresentation(title: "Alice", subtitle: "Family", body: "Secret", appLocked: true)
        XCTAssertEqual(result.title, "SpaceGram")
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
        XCTAssertTrue(SpaceGramPrivacyPolicyStore.saveAccountPolicy(SpaceGramPrivacyPolicy(hideNotificationSender: true), accountId: 1, mediaBoxPath: firstMediaBox, baseBundleId: nil))
        XCTAssertTrue(SpaceGramPrivacyPolicyStore.saveAccountPolicy(SpaceGramPrivacyPolicy(stripPhotoMetadata: true), accountId: 2, mediaBoxPath: secondMediaBox, baseBundleId: nil))
        XCTAssertTrue(SpaceGramPrivacyPolicyStore.loadAccountPolicy(mediaBoxPath: firstMediaBox).hideNotificationSender)
        XCTAssertFalse(SpaceGramPrivacyPolicyStore.loadAccountPolicy(mediaBoxPath: firstMediaBox).stripPhotoMetadata)
        XCTAssertTrue(SpaceGramPrivacyPolicyStore.loadAccountPolicy(mediaBoxPath: secondMediaBox).stripPhotoMetadata)

        SpaceGramPrivacyPolicyStore.clearAccountPolicy(accountId: 1, mediaBoxPath: firstMediaBox, baseBundleId: nil)
        XCTAssertEqual(SpaceGramPrivacyPolicyStore.loadAccountPolicy(mediaBoxPath: firstMediaBox), .default)
        XCTAssertTrue(SpaceGramPrivacyPolicyStore.loadAccountPolicy(mediaBoxPath: secondMediaBox).stripPhotoMetadata)
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

        guard let sanitized = SpaceGramMetadataSanitizer.sanitizeStillImage(encoded as Data),
              let source = CGImageSourceCreateWithData(sanitized as CFData, nil),
              CGImageSourceCreateImageAtIndex(source, 0, nil) != nil,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return XCTFail("Unable to sanitize test image")
        }
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
        XCTAssertNil(properties[kCGImagePropertyExifDictionary])
        XCTAssertNil(properties[kCGImagePropertyIPTCDictionary])
        XCTAssertNil(properties[kCGImagePropertyTIFFDictionary])
    }

    func testStillImageSanitizerNormalizesOrientationIntoPixels() throws {
        let pixels = Data([
            255, 0, 0, 255,
            0, 0, 255, 255
        ])
        let image = try XCTUnwrap(CGImage(
            width: 2,
            height: 1,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: 8,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: try XCTUnwrap(CGDataProvider(data: pixels as CFData)),
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ))
        let encoded = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(encoded, "public.jpeg" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: 6] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))

        let sanitized = try XCTUnwrap(SpaceGramMetadataSanitizer.sanitizeStillImage(encoded as Data))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(sanitized as CFData, nil))
        let normalized = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        XCTAssertEqual(normalized.width, 1)
        XCTAssertEqual(normalized.height, 2)
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
        XCTAssertNil(properties[kCGImagePropertyOrientation])
    }
}
