import AccountContext
import Display
import Foundation
import ItemListUI
import QwengramStrings
import PresentationDataUtils
import QwengramAI
import QwengramSettings
import QwengramSettingsSignal
import SwiftSignalKit
import TelegramPresentationData

private let qwengramTranslatorLanguages = ["English", "Russian", "Chinese", "Spanish", "German", "French", "Japanese", "Korean"]

private final class QwengramTranslatorArguments {
    let updateInput: (String) -> Void
    let selectTargetLanguage: () -> Void
    let translate: () -> Void

    init(updateInput: @escaping (String) -> Void, selectTargetLanguage: @escaping () -> Void, translate: @escaping () -> Void) {
        self.updateInput = updateInput
        self.selectTargetLanguage = selectTargetLanguage
        self.translate = translate
    }
}

private enum QwengramTranslatorEntry: ItemListNodeEntry {
    case header(Int32, Int32, String)
    case sourceLanguage(Int32, Int32)
    case targetLanguage(Int32, Int32, String, Bool)
    case input(Int32, Int32, String, Bool)
    case translate(Int32, Int32, Bool)
    case loading(Int32, Int32)
    case result(Int32, Int32, String)

    var section: ItemListSectionId {
        switch self {
        case let .header(_, section, _), let .sourceLanguage(_, section), let .targetLanguage(_, section, _, _), let .input(_, section, _, _), let .translate(_, section, _), let .loading(_, section), let .result(_, section, _):
            return section
        }
    }

    var stableId: Int32 {
        switch self {
        case let .header(id, _, _), let .sourceLanguage(id, _), let .targetLanguage(id, _, _, _), let .input(id, _, _, _), let .translate(id, _, _), let .loading(id, _), let .result(id, _, _):
            return id
        }
    }

    static func == (lhs: QwengramTranslatorEntry, rhs: QwengramTranslatorEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.header(lId, lSection, lText), .header(rId, rSection, rText)):
            return lId == rId && lSection == rSection && lText == rText
        case let (.sourceLanguage(lId, lSection), .sourceLanguage(rId, rSection)):
            return lId == rId && lSection == rSection
        case let (.targetLanguage(lId, lSection, lLanguage, lEnabled), .targetLanguage(rId, rSection, rLanguage, rEnabled)):
            return lId == rId && lSection == rSection && lLanguage == rLanguage && lEnabled == rEnabled
        case let (.input(lId, lSection, lText, lEnabled), .input(rId, rSection, rText, rEnabled)):
            return lId == rId && lSection == rSection && lText == rText && lEnabled == rEnabled
        case let (.translate(lId, lSection, lEnabled), .translate(rId, rSection, rEnabled)):
            return lId == rId && lSection == rSection && lEnabled == rEnabled
        case let (.loading(lId, lSection), .loading(rId, rSection)):
            return lId == rId && lSection == rSection
        case let (.result(lId, lSection, lText), .result(rId, rSection, rText)):
            return lId == rId && lSection == rSection && lText == rText
        default:
            return false
        }
    }

    static func < (lhs: QwengramTranslatorEntry, rhs: QwengramTranslatorEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! QwengramTranslatorArguments
        switch self {
        case let .header(_, section, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: section)
        case let .sourceLanguage(_, section):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "Source language", enabled: false, label: "Auto Detect", sectionId: section, style: .blocks, disclosureStyle: .none, action: {})
        case let .targetLanguage(_, section, language, enabled):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: "Target language", enabled: enabled, label: language, sectionId: section, style: .blocks, disclosureStyle: enabled ? .arrow : .none, action: enabled ? arguments.selectTargetLanguage : {})
        case let .input(_, section, text, enabled):
            return ItemListMultilineInputItem(presentationData: presentationData, text: text, placeholder: "Paste or type text to translate", maxLength: nil, sectionId: section, style: .blocks, textUpdated: enabled ? arguments.updateInput : { _ in })
        case let .translate(_, section, enabled):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Translate", kind: enabled ? .generic : .disabled, alignment: .natural, sectionId: section, style: .blocks, action: enabled ? arguments.translate : {})
        case let .loading(_, section):
            return ItemListTextItem(presentationData: presentationData, text: .plain("Translating…"), sectionId: section)
        case let .result(_, section, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: section)
        }
    }
}

public func qwengramTranslatorController(context: AccountContext, initialText: String = "") -> ViewController {
    let updatePromise = ValuePromise<Int32>(0, ignoreRepeated: false)
    var updateValue: Int32 = 0
    var input = initialText
    var targetLanguage = qwengramTranslatorLanguages[0]
    var result: String?
    var isTranslating = false
    weak var controller: ItemListController?
    let refresh: () -> Void = {
        updateValue += 1
        updatePromise.set(updateValue)
    }
    let showError: (String) -> Void = { text in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        controller?.present(textAlertController(context: context, title: "Translator", text: text, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), in: .window(.root))
    }
    let arguments = QwengramTranslatorArguments(updateInput: { value in
        input = value
    }, selectTargetLanguage: {
        guard !isTranslating else {
            return
        }
        let actions = qwengramTranslatorLanguages.map { language in
            TextAlertAction(type: .defaultAction, title: language, action: {
                targetLanguage = language
                refresh()
            })
        }
        controller?.present(textAlertController(context: context, title: "Target language", text: "Choose a language", actions: actions), in: .window(.root))
    }, translate: {
        guard QwengramSettings.shared.qwengramEnabled else {
            showError(ngI18n("Qwengram.Disabled", context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode))
            return
        }
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            showError("Enter text to translate.")
            return
        }
        guard !isTranslating else {
            return
        }
        let apiKey: String
        do {
            guard let storedKey = try QwengramAIKeychain.loadQwenAPIKey(), !storedKey.isEmpty else {
                showError("Configure Qwen Provider in Qwengram Settings → AI before translating.")
                return
            }
            apiKey = storedKey
        } catch {
            showError("Unable to access the Qwen API key. Configure Qwen Provider in Qwengram Settings → AI.")
            return
        }
        let model = QwengramSettings.shared.qwenModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            showError("Configure a Qwen model in Qwengram Settings → AI before translating.")
            return
        }

        isTranslating = true
        result = nil
        refresh()
        let messages = [
            QwengramAIMessage(role: .system, content: "You are a translation engine. Translate accurately into the requested target language. Preserve meaning, formatting, names, URLs, and important details. Return only the translated text unless clarification is necessary."),
            QwengramAIMessage(role: .user, content: "Target language: \(targetLanguage)\n\nText:\n\(text)"),
        ]
        QwengramQwenProvider(apiKey: apiKey).generateText(model: model, messages: messages) { requestResult in
            Queue.mainQueue().async {
                isTranslating = false
                switch requestResult {
                case let .success(translation):
                    let trimmedTranslation = translation.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmedTranslation.isEmpty {
                        showError("Qwen returned an empty translation. Try again.")
                    } else {
                        result = trimmedTranslation
                    }
                case let .failure(error):
                    let message: String
                    switch error {
                    case .disabled:
                        message = ngI18n("Qwengram.Disabled", context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode)
                    case .invalidRequest:
                        message = "The Qwen request could not be created. Check the Qwen Provider settings."
                    case .network:
                        message = "Unable to reach Qwen. Check your network connection and try again."
                    case let .httpStatus(status):
                        message = "Qwen returned an error (HTTP \(status)). Check your Provider settings and try again."
                    case .decoding:
                        message = "Qwen returned an unreadable response. Try again later."
                    case .emptyResponse:
                        message = "Qwen returned an empty translation. Try again."
                    case .streamEndedUnexpectedly:
                        message = "Qwen stopped responding unexpectedly. Try again."
                    }
                    showError(message)
                }
                refresh()
            }
        }
    })
    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, updatePromise.get(), qwengramEnabledSignal())
    |> map { presentationData, _, enabled -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let listPresentationData = ItemListPresentationData(presentationData)
        var entries: [QwengramTranslatorEntry] = [
            .header(0, 0, "Source language"),
            .sourceLanguage(1, 0),
            .header(2, 1, "Target language"),
            .targetLanguage(3, 1, targetLanguage, !isTranslating),
            .header(4, 2, "Text"),
            .input(5, 2, input, !isTranslating),
            .translate(6, 3, enabled && !isTranslating),
        ]
        if isTranslating {
            entries.append(.loading(7, 3))
        }
        if let result {
            entries.append(.header(8, 4, "Translation"))
            entries.append(.result(9, 4, result))
        }
        let controllerState = ItemListControllerState(presentationData: listPresentationData, title: .text("Translator"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        return (controllerState, (ItemListNodeState(presentationData: listPresentationData, entries: entries, style: .blocks, animateChanges: true), arguments))
    }
    let itemListController = ItemListController(context: context, state: signal)
    itemListController.navigationPresentation = .default
    controller = itemListController
    return itemListController
}
