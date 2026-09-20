import AccountContext
import Display
import Foundation
import ItemListUI
import NagramTranslate
import PresentationDataUtils
import SpaceGramAppearance
import SpaceGramSettings
import SpaceGramSettingsSignal
import SpaceGramStrings
import SwiftSignalKit
import TelegramPresentationData

private final class SpaceGramTranslatorArguments {
    let updateInput: (String) -> Void
    let selectSourceLanguage: () -> Void
    let selectTargetLanguage: () -> Void
    let translate: () -> Void

    init(updateInput: @escaping (String) -> Void, selectSourceLanguage: @escaping () -> Void, selectTargetLanguage: @escaping () -> Void, translate: @escaping () -> Void) {
        self.updateInput = updateInput
        self.selectSourceLanguage = selectSourceLanguage
        self.selectTargetLanguage = selectTargetLanguage
        self.translate = translate
    }
}

private enum SpaceGramTranslatorEntry: ItemListNodeEntry {
    case header(Int32, Int32, String)
    case sourceLanguage(Int32, Int32, String, Bool)
    case targetLanguage(Int32, Int32, String, Bool)
    case input(Int32, Int32, String, String, Bool)
    case translate(Int32, Int32, String, Bool)
    case loading(Int32, Int32, String)
    case result(Int32, Int32, String, String)

    var section: ItemListSectionId {
        switch self {
        case let .header(_, section, _), let .sourceLanguage(_, section, _, _), let .targetLanguage(_, section, _, _), let .input(_, section, _, _, _), let .translate(_, section, _, _), let .loading(_, section, _), let .result(_, section, _, _):
            return section
        }
    }

    var stableId: Int32 {
        switch self {
        case let .header(id, _, _), let .sourceLanguage(id, _, _, _), let .targetLanguage(id, _, _, _), let .input(id, _, _, _, _), let .translate(id, _, _, _), let .loading(id, _, _), let .result(id, _, _, _):
            return id
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case let (.header(lId, lSection, lText), .header(rId, rSection, rText)):
            return lId == rId && lSection == rSection && lText == rText
        case let (.sourceLanguage(lId, lSection, lLanguage, lEnabled), .sourceLanguage(rId, rSection, rLanguage, rEnabled)), let (.targetLanguage(lId, lSection, lLanguage, lEnabled), .targetLanguage(rId, rSection, rLanguage, rEnabled)):
            return lId == rId && lSection == rSection && lLanguage == rLanguage && lEnabled == rEnabled
        case let (.input(lId, lSection, lText, lPlaceholder, lEnabled), .input(rId, rSection, rText, rPlaceholder, rEnabled)):
            return lId == rId && lSection == rSection && lText == rText && lPlaceholder == rPlaceholder && lEnabled == rEnabled
        case let (.translate(lId, lSection, lTitle, lEnabled), .translate(rId, rSection, rTitle, rEnabled)):
            return lId == rId && lSection == rSection && lTitle == rTitle && lEnabled == rEnabled
        case let (.loading(lId, lSection, lText), .loading(rId, rSection, rText)), let (.result(lId, lSection, lText, _), .result(rId, rSection, rText, _)):
            return lId == rId && lSection == rSection && lText == rText
        default:
            return false
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.stableId < rhs.stableId }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! SpaceGramTranslatorArguments
        switch self {
        case let .header(_, section, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: section)
        case let .sourceLanguage(_, section, language, enabled):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: language, enabled: enabled, label: "", sectionId: section, style: .blocks, disclosureStyle: enabled ? .arrow : .none, action: enabled ? arguments.selectSourceLanguage : {})
        case let .targetLanguage(_, section, language, enabled):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: language, enabled: enabled, label: "", sectionId: section, style: .blocks, disclosureStyle: enabled ? .arrow : .none, action: enabled ? arguments.selectTargetLanguage : {})
        case let .input(_, section, text, placeholder, enabled):
            return ItemListMultilineInputItem(presentationData: presentationData, text: text, placeholder: placeholder, maxLength: nil, sectionId: section, style: .blocks, textUpdated: enabled ? arguments.updateInput : { _ in })
        case let .translate(_, section, title, enabled):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: enabled ? .generic : .disabled, alignment: .natural, sectionId: section, style: .blocks, action: enabled ? arguments.translate : {})
        case let .loading(_, section, text), let .result(_, section, text, _):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: section)
        }
    }
}

private struct SpaceGramLanguagePickerEntry: ItemListNodeEntry {
    let stableId: Int32
    let title: String
    let selected: Bool
    let action: () -> Void

    var section: ItemListSectionId { 0 }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.stableId == rhs.stableId && lhs.title == rhs.title && lhs.selected == rhs.selected }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.stableId < rhs.stableId }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: selected ? "✓" : "", sectionId: section, style: .blocks, disclosureStyle: .none, action: action)
    }
}

private func spaceGramLanguagePickerController(context: AccountContext, titleKey: String, languages: [SpaceGramTranslationLanguage], selected: SpaceGramTranslationLanguage, updated: @escaping (SpaceGramTranslationLanguage) -> Void) -> ViewController {
    weak var controller: ItemListController?
    let signal = context.sharedContext.presentationData
    |> map { presentationData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let lang = presentationData.strings.baseLanguageCode
        let entries = languages.enumerated().map { index, language in
            SpaceGramLanguagePickerEntry(stableId: Int32(index), title: ngI18n(language.localizationKey, lang), selected: language == selected, action: {
                updated(language)
                (controller?.navigationController as? NavigationController)?.popViewController(animated: true)
            })
        }
        let data = spaceGramItemListPresentationData(presentationData)
        let state = ItemListControllerState(presentationData: data, title: .text(ngI18n(titleKey, lang)), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        return (state, (ItemListNodeState(presentationData: data, entries: entries, style: .blocks, animateChanges: false), NSNull()))
    }
    let result = ItemListController(context: context, state: signal)
    controller = result
    return result
}

public func spaceGramTranslatorController(context: AccountContext, initialText: String = "") -> ViewController {
    let updatePromise = ValuePromise<Int32>(0, ignoreRepeated: false)
    let translationDisposable = MetaDisposable()
    var updateValue: Int32 = 0
    var input = initialText
    var sourceLanguage = SpaceGramTranslationLanguage.automatic
    var targetLanguage = SpaceGramTranslationLanguage.targetLanguages[0]
    var result: String?
    var isTranslating = false
    weak var controller: ItemListController?
    var push: ((ViewController) -> Void)?
    let refresh: () -> Void = { updateValue += 1; updatePromise.set(updateValue) }
    let showError: (String) -> Void = { text in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        controller?.present(textAlertController(context: context, title: ngI18n("SpaceGram.Translator.Title", presentationData.strings.baseLanguageCode), text: text, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), in: .window(.root))
    }
    let arguments = SpaceGramTranslatorArguments(updateInput: { input = $0 }, selectSourceLanguage: {
        guard !isTranslating else { return }
        push?(spaceGramLanguagePickerController(context: context, titleKey: "SpaceGram.Translator.Source", languages: SpaceGramTranslationLanguage.sourceLanguages, selected: sourceLanguage, updated: { sourceLanguage = $0; refresh() }))
    }, selectTargetLanguage: {
        guard !isTranslating else { return }
        push?(spaceGramLanguagePickerController(context: context, titleKey: "SpaceGram.Translator.Target", languages: SpaceGramTranslationLanguage.targetLanguages, selected: targetLanguage, updated: { targetLanguage = $0; refresh() }))
    }, translate: {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let lang = presentationData.strings.baseLanguageCode
        guard SpaceGramSettings.shared.spaceGramEnabled else { showError(ngI18n("SpaceGram.Disabled", lang)); return }
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { showError(ngI18n("SpaceGram.Translator.Empty", lang)); return }
        guard !isTranslating, let targetCode = targetLanguage.code else { return }
        isTranslating = true
        result = nil
        refresh()
        translationDisposable.set((NagramTranslateService(context: context).translate(text: text, toLang: targetCode, fromLang: sourceLanguage.code)
        |> deliverOnMainQueue).startStrict(next: { value in
            isTranslating = false
            if let translated = value?.0.trimmingCharacters(in: .whitespacesAndNewlines), !translated.isEmpty {
                result = translated
            } else {
                showError(ngI18n("SpaceGram.Translator.Failed", lang))
            }
            refresh()
        }, error: { _ in
            isTranslating = false
            showError(ngI18n("SpaceGram.Translator.Failed", lang))
            refresh()
        }))
    })
    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, updatePromise.get(), spaceGramEnabledSignal())
    |> map { presentationData, _, enabled -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let lang = presentationData.strings.baseLanguageCode
        let data = spaceGramItemListPresentationData(presentationData)
        var entries: [SpaceGramTranslatorEntry] = [
            .header(0, 0, ngI18n("SpaceGram.Translator.Source", lang)),
            .sourceLanguage(1, 0, ngI18n(sourceLanguage.localizationKey, lang), !isTranslating),
            .header(2, 1, ngI18n("SpaceGram.Translator.Target", lang)),
            .targetLanguage(3, 1, ngI18n(targetLanguage.localizationKey, lang), !isTranslating),
            .header(4, 2, ngI18n("SpaceGram.Translator.Text", lang)),
            .input(5, 2, input, ngI18n("SpaceGram.Translator.Placeholder", lang), !isTranslating),
            .translate(6, 3, ngI18n("SpaceGram.Translator.Translate", lang), enabled && !isTranslating),
        ]
        if isTranslating { entries.append(.loading(7, 3, ngI18n("SpaceGram.Translator.Loading", lang))) }
        if let result {
            entries.append(.header(8, 4, ngI18n("SpaceGram.Translator.Result", lang)))
            entries.append(.result(9, 4, result, result))
        }
        let state = ItemListControllerState(presentationData: data, title: .text(ngI18n("SpaceGram.Translator.Title", lang)), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        return (state, (ItemListNodeState(presentationData: data, entries: entries, style: .blocks, animateChanges: true), arguments))
    }
    let itemListController = ItemListController(context: context, state: signal)
    itemListController.navigationPresentation = .default
    controller = itemListController
    push = { [weak itemListController] value in (itemListController?.navigationController as? NavigationController)?.pushViewController(value, animated: true) }
    return itemListController
}
