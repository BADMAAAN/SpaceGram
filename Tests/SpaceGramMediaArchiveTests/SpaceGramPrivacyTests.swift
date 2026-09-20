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
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifUserComment: "private",
                kCGImagePropertyExifDateTimeOriginal: "2026:09:20 12:34:56"
            ],
            kCGImagePropertyIPTCDictionary: [kCGImagePropertyIPTCCaptionAbstract: "private caption"],
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFImageDescription: "private description"]
        ]
        CGImageDestinationAddImage(destination, image, metadata as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        guard let originalSource = CGImageSourceCreateWithData(encoded as CFData, nil),
              let originalProperties = CGImageSourceCopyPropertiesAtIndex(originalSource, 0, nil) as? [CFString: Any] else {
            return XCTFail("Unable to inspect test image")
        }
        XCTAssertNotNil(originalProperties[kCGImagePropertyGPSDictionary])
        XCTAssertNotNil(originalProperties[kCGImagePropertyExifDictionary])
        XCTAssertNotNil(originalProperties[kCGImagePropertyIPTCDictionary])
        XCTAssertNotNil(originalProperties[kCGImagePropertyTIFFDictionary])

        let sanitized = try XCTUnwrap(
            SpaceGramMetadataSanitizer.sanitizeStillImage(encoded as Data),
            "scenario=private-jpeg stage=sanitize inputBytes=\(encoded.length)"
        )
        let source = try XCTUnwrap(CGImageSourceCreateWithData(sanitized as CFData, nil), "scenario=private-jpeg stage=output-source")
        XCTAssertEqual(CGImageSourceGetType(source).map { $0 as String }, "public.jpeg", "scenario=private-jpeg stage=output-type")
        XCTAssertNotNil(CGImageSourceCreateImageAtIndex(source, 0, nil), "scenario=private-jpeg stage=output-decode")
        let properties = try XCTUnwrap(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            "scenario=private-jpeg stage=output-properties"
        )
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary], "scenario=private-jpeg metadata=GPS")
        XCTAssertNil(properties[kCGImagePropertyIPTCDictionary], "scenario=private-jpeg metadata=IPTC")
        XCTAssertNil(properties[kCGImagePropertyTIFFDictionary], "scenario=private-jpeg metadata=TIFF")
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any]
        XCTAssertNil(exif?[kCGImagePropertyExifUserComment], "scenario=private-jpeg metadata=EXIF.UserComment")
        XCTAssertNil(exif?[kCGImagePropertyExifDateTimeOriginal], "scenario=private-jpeg metadata=EXIF.DateTimeOriginal")
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

    func testStillImageSanitizerNormalizesAllExifOrientations() throws {
        let image = try makeOrientationPatternImage()
        for orientation in 1 ... 8 {
            let encoded = try encode(image: image, type: "public.jpeg", properties: [
                kCGImagePropertyOrientation: orientation,
                kCGImageDestinationLossyCompressionQuality: 1.0
            ])
            let sanitized = try XCTUnwrap(
                SpaceGramMetadataSanitizer.sanitizeStillImage(encoded),
                "scenario=orientation-\(orientation) stage=sanitize inputBytes=\(encoded.count)"
            )
            let source = try XCTUnwrap(CGImageSourceCreateWithData(sanitized as CFData, nil), "scenario=orientation-\(orientation) stage=output-source")
            let normalized = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil), "scenario=orientation-\(orientation) stage=output-decode")
            let expected = expectedOrientationGrid(orientation)
            XCTAssertEqual(normalized.width, expected.columns * 20, "scenario=orientation-\(orientation) stage=width")
            XCTAssertEqual(normalized.height, expected.rows * 20, "scenario=orientation-\(orientation) stage=height")
            let rendered = try rgbaPixels(from: normalized)
            for row in 0 ..< expected.rows {
                for column in 0 ..< expected.columns {
                    let x = column * 20 + 10
                    let y = row * 20 + 10
                    let offset = y * rendered.bytesPerRow + x * 4
                    let actual = (rendered.pixels[offset], rendered.pixels[offset + 1], rendered.pixels[offset + 2])
                    let expectedColor = expected.colors[row * expected.columns + column]
                    XCTAssertLessThanOrEqual(abs(Int(actual.0) - Int(expectedColor.0)), 60, "scenario=orientation-\(orientation) cell=\(column),\(row) channel=red")
                    XCTAssertLessThanOrEqual(abs(Int(actual.1) - Int(expectedColor.1)), 60, "scenario=orientation-\(orientation) cell=\(column),\(row) channel=green")
                    XCTAssertLessThanOrEqual(abs(Int(actual.2) - Int(expectedColor.2)), 60, "scenario=orientation-\(orientation) cell=\(column),\(row) channel=blue")
                }
            }
            let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
            XCTAssertNil(properties[kCGImagePropertyOrientation], "scenario=orientation-\(orientation) metadata=orientation")
        }
    }

    func testStillImageSanitizerPreservesPNGAndTransparency() throws {
        let pixels = Data([
            255, 0, 0, 64,
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
        let encoded = try encode(image: image, type: "public.png")
        let sanitized = try XCTUnwrap(SpaceGramMetadataSanitizer.sanitizeStillImage(encoded), "scenario=transparent-png stage=sanitize")
        let source = try XCTUnwrap(CGImageSourceCreateWithData(sanitized as CFData, nil), "scenario=transparent-png stage=output-source")
        XCTAssertEqual(CGImageSourceGetType(source).map { $0 as String }, "public.png")
        let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil), "scenario=transparent-png stage=output-decode")
        let rendered = try rgbaPixels(from: decoded)
        XCTAssertLessThan(rendered.pixels[3], 128, "scenario=transparent-png pixel=0 alpha")
        XCTAssertGreaterThan(rendered.pixels[7], 240, "scenario=transparent-png pixel=1 alpha")
    }

    func testStillImageSanitizerRejectsMultiframeInput() throws {
        let image = try makeOrientationPatternImage()
        let encoded = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(encoded, "com.compuserve.gif" as CFString, 2, nil))
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        XCTAssertNil(SpaceGramMetadataSanitizer.sanitizeStillImage(encoded as Data))
    }

    private typealias RGB = (UInt8, UInt8, UInt8)

    private func makeOrientationPatternImage() throws -> CGImage {
        let colors: [RGB] = [
            (255, 0, 0), (0, 255, 0), (0, 0, 255),
            (255, 255, 0), (255, 0, 255), (0, 255, 255)
        ]
        let width = 60
        let height = 40
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0 ..< height {
            for x in 0 ..< width {
                let color = colors[(y / 20) * 3 + x / 20]
                let offset = (y * width + x) * 4
                pixels[offset] = color.0
                pixels[offset + 1] = color.1
                pixels[offset + 2] = color.2
            }
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
        return try XCTUnwrap(CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ))
    }

    private func encode(image: CGImage, type: String, properties: [CFString: Any]? = nil) throws -> Data {
        let encoded = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(encoded, type as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, properties.map { $0 as CFDictionary })
        XCTAssertTrue(CGImageDestinationFinalize(destination), "type=\(type) stage=fixture-finalize")
        return encoded as Data
    }

    private func rgbaPixels(from image: CGImage) throws -> (pixels: [UInt8], bytesPerRow: Int) {
        let bytesPerRow = image.width * 4
        var pixels = [UInt8](repeating: 0, count: bytesPerRow * image.height)
        try pixels.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(
                data: bytes.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.translateBy(x: 0, y: CGFloat(image.height))
            context.scaleBy(x: 1, y: -1)
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return (pixels, bytesPerRow)
    }

    private func expectedOrientationGrid(_ orientation: Int) -> (columns: Int, rows: Int, colors: [RGB]) {
        let red: RGB = (255, 0, 0)
        let green: RGB = (0, 255, 0)
        let blue: RGB = (0, 0, 255)
        let yellow: RGB = (255, 255, 0)
        let magenta: RGB = (255, 0, 255)
        let cyan: RGB = (0, 255, 255)
        switch orientation {
        case 2: return (3, 2, [blue, green, red, cyan, magenta, yellow])
        case 3: return (3, 2, [cyan, magenta, yellow, blue, green, red])
        case 4: return (3, 2, [yellow, magenta, cyan, red, green, blue])
        case 5: return (2, 3, [red, yellow, green, magenta, blue, cyan])
        case 6: return (2, 3, [yellow, red, magenta, green, cyan, blue])
        case 7: return (2, 3, [cyan, blue, magenta, green, yellow, red])
        case 8: return (2, 3, [blue, cyan, green, magenta, red, yellow])
        default: return (3, 2, [red, green, blue, yellow, magenta, cyan])
        }
    }
}
