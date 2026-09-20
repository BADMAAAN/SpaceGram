import SpaceGramSettings
import SpaceGramSettingsUI
import XCTest

final class SpaceGramToolsContractTests: XCTestCase {
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
