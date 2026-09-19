// Derived from Nagram-iOS. Copyright NextAlone and Nagram-iOS contributors.
import AppBundle
import Foundation

// MARK: NAGRAM — 本地化管理器（精简：去掉远程下载/日志）。
// 从主 app bundle 的 <locale>.lproj/SpaceGramLocalizable.strings 读取，未命中按 fallback 链回退，最终回退 en。

public let spaceGramFallbackLocale = "en"

public final class SpaceGramLocalization {
    public static let shared = SpaceGramLocalization()

    private let appBundle: Bundle
    private var localizations: [String: [String: String]] = [:]
    private let fallbackMappings: [String: String] = [
        "zh-hant": "zh-hans"
    ]

    private init() {
        self.appBundle = getAppBundle()
        for locale in self.appBundle.localizations where locale != "Base" {
            self.localizations[locale] = self.loadDictionary(for: locale)
        }
    }

    public func localizedString(_ key: String, _ locale: String = spaceGramFallbackLocale, args: CVarArg...) -> String {
        let sanitized = self.sanitize(locale)
        if let value = self.find(key, inLocale: sanitized) {
            return args.isEmpty ? value : String(format: value, arguments: args)
        }
        return key
    }

    private func loadDictionary(for locale: String) -> [String: String] {
        guard let path = self.appBundle.path(forResource: "SpaceGramLocalizable", ofType: "strings", inDirectory: nil, forLocalization: locale),
              let dictionary = NSDictionary(contentsOf: URL(fileURLWithPath: path)) as? [String: String]
        else {
            return [:]
        }
        return dictionary
    }

    private func sanitize(_ locale: String) -> String {
        var result = locale
        let rawSuffix = "-raw"
        if result.hasSuffix(rawSuffix) {
            result = String(result.dropLast(rawSuffix.count))
        }
        result = result.replacingOccurrences(of: "_", with: "-").lowercased()
        // Telegram language packs may use region/variant suffixes. Never consult
        // the keyboard language: UI language comes from PresentationData.
        if result == "ru" || result.hasPrefix("ru-") { return "ru" }
        if result == "en" || result.hasPrefix("en-") { return "en" }
        return result
    }

    private func find(_ key: String, inLocale locale: String) -> String? {
        if let value = self.localizations[locale]?[key], !value.isEmpty {
            return value
        }
        if let fallback = self.fallbackMappings[locale] {
            return self.find(key, inLocale: fallback)
        }
        return self.localizations[spaceGramFallbackLocale]?[key]
    }
}

/// 便捷函数：`ngI18n("Nagram.X", lang)`。lang 通常取 `presentationData.strings.baseLanguageCode`。
public func ngI18n(_ key: String, _ locale: String = spaceGramFallbackLocale) -> String {
    return SpaceGramLocalization.shared.localizedString(key, locale)
}
