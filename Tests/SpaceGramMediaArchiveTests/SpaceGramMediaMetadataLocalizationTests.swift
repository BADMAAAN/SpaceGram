import Foundation
import NagramMediaMetadata
import SpaceGramStrings
import XCTest

final class SpaceGramMediaMetadataLocalizationTests: XCTestCase {
    private func makeLocalization() -> SpaceGramLocalization {
        return SpaceGramLocalization(appBundle: Bundle(for: SpaceGramMediaMetadataLocalizationTests.self))
    }

    func testLocalizationResourcesAreBundled() {
        let localization = self.makeLocalization()
        XCTAssertEqual(localization.bundleURL.pathExtension, "xctest")
        for locale in ["en", "ru"] {
            guard let resourceURL = localization.localizedResourceURL(locale: locale) else {
                XCTFail("Missing \(locale).lproj/SpaceGramLocalizable.strings in bundle \(localization.bundleURL.path)")
                continue
            }
            XCTAssertTrue(
                resourceURL.path.hasPrefix(localization.bundleURL.path + "/"),
                "Resolved \(locale) localization outside test bundle: \(resourceURL.path)"
            )
        }
    }

    func testEnglishMediaInformationLabels() {
        let localization = self.makeLocalization()
        let labels = NagramMediaMetadata.localizedLabels(locale: "en", localization: localization)
        XCTAssertEqual(labels["title"], "Media Information")
        XCTAssertEqual(labels["resolution"], "Resolution")
        XCTAssertEqual(labels["fileSize"], "File Size")
        XCTAssertEqual(labels["type"], "Type")

        let fallbackLabels = NagramMediaMetadata.localizedLabels(
            locale: "unsupported-test-locale",
            localization: localization
        )
        XCTAssertEqual(fallbackLabels["title"], "Media Information")
    }

    func testRussianMediaInformationLabels() {
        let labels = NagramMediaMetadata.localizedLabels(
            locale: "ru-RU",
            localization: self.makeLocalization()
        )
        XCTAssertEqual(labels["title"], "Информация о медиа")
        XCTAssertEqual(labels["resolution"], "Разрешение")
        XCTAssertEqual(labels["fileSize"], "Размер файла")
        XCTAssertEqual(labels["type"], "Тип")
    }
}
