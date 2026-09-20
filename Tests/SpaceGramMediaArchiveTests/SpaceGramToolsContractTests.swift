import Foundation
import CoreImage
import SpaceGramQR
import SpaceGramSettings
import SpaceGramSettingsUI
import UIKit
import XCTest

final class SpaceGramToolsContractTests: XCTestCase {
    func testQRResultDecodesOriginalUTF8() throws {
        let detector = try XCTUnwrap(CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
        for text in ["hello", "https://example.org/a?q=1", "Привет", "🌌🙂", "first\nsecond", String(repeating: "a", count: SpaceGramQRGenerator.maximumUTF8Bytes)] {
            let image = try XCTUnwrap(SpaceGramQRGenerator.image(text: text)?.cgImage)
            let decoded = detector.features(in: CIImage(cgImage: image)).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
            XCTAssertEqual(decoded, [text])
        }
        XCTAssertNil(SpaceGramQRGenerator.image(text: String(repeating: "a", count: SpaceGramQRGenerator.maximumUTF8Bytes + 1)))
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
        XCTAssertNotNil(SpaceGramQRGenerator.image(text: "SpaceGram 🌌 Привет 你好"))
        XCTAssertNotNil(SpaceGramQRGenerator.image(text: String(repeating: "SpaceGram-", count: 50)))
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
