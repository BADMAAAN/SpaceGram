import Foundation

public struct SpaceGramTranslationLanguage: Equatable {
    public let code: String?
    public let localizationKey: String

    public init(code: String?, localizationKey: String) {
        self.code = code
        self.localizationKey = localizationKey
    }

    public static let automatic = SpaceGramTranslationLanguage(code: nil, localizationKey: "SpaceGram.Translator.Auto")

    public static let supported: [SpaceGramTranslationLanguage] = [
        SpaceGramTranslationLanguage(code: "en", localizationKey: "SpaceGram.Language.en"),
        SpaceGramTranslationLanguage(code: "ru", localizationKey: "SpaceGram.Language.ru"),
        SpaceGramTranslationLanguage(code: "zh", localizationKey: "SpaceGram.Language.zh"),
        SpaceGramTranslationLanguage(code: "es", localizationKey: "SpaceGram.Language.es"),
        SpaceGramTranslationLanguage(code: "de", localizationKey: "SpaceGram.Language.de"),
        SpaceGramTranslationLanguage(code: "fr", localizationKey: "SpaceGram.Language.fr"),
        SpaceGramTranslationLanguage(code: "it", localizationKey: "SpaceGram.Language.it"),
        SpaceGramTranslationLanguage(code: "ja", localizationKey: "SpaceGram.Language.ja"),
        SpaceGramTranslationLanguage(code: "ko", localizationKey: "SpaceGram.Language.ko"),
        SpaceGramTranslationLanguage(code: "pt-BR", localizationKey: "SpaceGram.Language.pt-BR"),
        SpaceGramTranslationLanguage(code: "uk", localizationKey: "SpaceGram.Language.uk"),
        SpaceGramTranslationLanguage(code: "ar", localizationKey: "SpaceGram.Language.ar"),
    ]

    public static let sourceLanguages: [SpaceGramTranslationLanguage] = [.automatic] + supported
    public static let targetLanguages: [SpaceGramTranslationLanguage] = supported
}
