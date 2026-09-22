import NagramMediaMetadata
import XCTest

final class SpaceGramMediaMetadataLocalizationTests: XCTestCase {
    func testEnglishMediaInformationLabels() {
        let labels = NagramMediaMetadata.localizedLabels(locale: "en")
        XCTAssertEqual(labels["title"], "Media Information")
        XCTAssertEqual(labels["resolution"], "Resolution")
        XCTAssertEqual(labels["fileSize"], "File Size")
        XCTAssertEqual(labels["type"], "Type")
    }

    func testRussianMediaInformationLabels() {
        let labels = NagramMediaMetadata.localizedLabels(locale: "ru-RU")
        XCTAssertEqual(labels["title"], "Информация о медиа")
        XCTAssertEqual(labels["resolution"], "Разрешение")
        XCTAssertEqual(labels["fileSize"], "Размер файла")
        XCTAssertEqual(labels["type"], "Тип")
    }
}
