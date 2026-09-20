import Foundation
import CoreImage
import SpaceGramQR
import SpaceGramSettings
import SpaceGramSettingsUI
import UIKit
import XCTest

final class SpaceGramToolsContractTests: XCTestCase {
    func testQRResultDecodesOriginalUTF8() throws {
        let detector = try XCTUnwrap(
            CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]),
            "stage=detector-creation"
        )
        let scenarios = [
            ("ascii", "hello"),
            ("russian", "Привет"),
            ("chinese", "你好"),
            ("emoji", "🌌🙂"),
            ("url", "https://example.org/a?q=1"),
            ("newlines", "first\nsecond"),
            ("long-mixed", String(repeating: "SpaceGram-", count: 50)),
            ("byte-limit", String(repeating: "a", count: SpaceGramQRGenerator.maximumUTF8Bytes))
        ]
        for (scenario, text) in scenarios {
            let bytes = text.utf8.count
            let image = try XCTUnwrap(
                SpaceGramQRGenerator.image(text: text),
                "scenario=\(scenario) utf8Bytes=\(bytes) stage=ui-image"
            )
            let cgImage = try XCTUnwrap(
                image.cgImage,
                "scenario=\(scenario) utf8Bytes=\(bytes) stage=cg-image"
            )
            XCTAssertEqual(cgImage.width, cgImage.height, "scenario=\(scenario) utf8Bytes=\(bytes) stage=pixel-dimensions")
            XCTAssertGreaterThan(cgImage.width, 0, "scenario=\(scenario) utf8Bytes=\(bytes) stage=pixel-dimensions")
            let decoded = detector.features(in: CIImage(cgImage: cgImage)).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
            XCTAssertEqual(decoded, [text], "scenario=\(scenario) utf8Bytes=\(bytes) stage=decoding")
        }
        let overLimitUTF8 = String(repeating: "🙂", count: SpaceGramQRGenerator.maximumUTF8Bytes / 4 + 1)
        XCTAssertGreaterThan(Data(overLimitUTF8.utf8).count, SpaceGramQRGenerator.maximumUTF8Bytes)
        XCTAssertNil(SpaceGramQRGenerator.image(text: overLimitUTF8))
        for scale in [CGFloat.nan, .infinity, 0, -1, 1.5, 17, .greatestFiniteMagnitude] {
            XCTAssertNil(SpaceGramQRGenerator.image(text: "test", scale: scale))
        }
    }

    func testPreviewConstructsOffMainAndLoadsOnMainRepeatedly() {
        let finished = expectation(description: "production preview path")
        DispatchQueue.global().async {
            for _ in 0 ..< 10 {
                // This is the actual node used by the ItemList, not a mock.
                let node = SpaceGramQRImageItemNode()
                DispatchQueue.main.sync { XCTAssertNotNil(node.view) }
            }
            // Navigation can discard an unmounted node before its view loads.
            _ = SpaceGramQRImageItemNode()
            finished.fulfill()
        }
        wait(for: [finished], timeout: 10)
    }
    func testQRGeneratorRejectsEmptyText() {
        XCTAssertNil(SpaceGramQRGenerator.image(text: ""))
    }

    func testQRGeneratorAcceptsUTF8AndLongishText() {
        let unicode = "SpaceGram 🌌 Привет 你好"
        let long = String(repeating: "SpaceGram-", count: 50)
        XCTAssertNotNil(SpaceGramQRGenerator.image(text: unicode), "scenario=unicode utf8Bytes=\(unicode.utf8.count) stage=ui-image")
        XCTAssertNotNil(SpaceGramQRGenerator.image(text: long), "scenario=long utf8Bytes=\(long.utf8.count) stage=ui-image")
    }

    func testTranslationLanguageModel() {
        XCTAssertNil(SpaceGramTranslationLanguage.sourceLanguages.first?.code)
        XCTAssertFalse(SpaceGramTranslationLanguage.targetLanguages.contains(where: { $0.code == nil }))
        XCTAssertEqual(Set(SpaceGramTranslationLanguage.supported.compactMap(\.code)).count, SpaceGramTranslationLanguage.supported.count)
        XCTAssertTrue(SpaceGramTranslationLanguage.supported.contains(where: { $0.code == "ru" }))
        XCTAssertTrue(SpaceGramTranslationLanguage.supported.contains(where: { $0.code == "en" }))
    }

    func testAppIconIdentifierMapping() {
        XCTAssertNil(SpaceGramAppIcon.default.alternateIconName)
        XCTAssertEqual(SpaceGramAppIcon.allCases.map(\.rawValue), ["Default", "Moon", "Earth", "Mars", "Sun", "Saturn", "Neptune"])
        XCTAssertEqual(SpaceGramAppIcon.moon.alternateIconName, "Moon")
        XCTAssertEqual(SpaceGramAppIcon.neptune.alternateIconName, "Neptune")
    }
}
