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

private final class QwengramSummarizerArguments {
    let updateInput: (String) -> Void
    let summarize: () -> Void

    init(updateInput: @escaping (String) -> Void, summarize: @escaping () -> Void) {
        self.updateInput = updateInput
        self.summarize = summarize
    }
}

private enum QwengramSummarizerEntry: ItemListNodeEntry {
    case header(Int32, Int32, String)
    case input(Int32, Int32, String, Bool)
    case summarize(Int32, Int32, Bool)
    case loading(Int32, Int32)
    case result(Int32, Int32, String)

    var section: ItemListSectionId {
        switch self {
        case let .header(_, section, _), let .input(_, section, _, _), let .summarize(_, section, _), let .loading(_, section), let .result(_, section, _):
            return section
        }
    }

    var stableId: Int32 {
        switch self {
        case let .header(id, _, _), let .input(id, _, _, _), let .summarize(id, _, _), let .loading(id, _), let .result(id, _, _):
            return id
        }
    }

    static func == (lhs: QwengramSummarizerEntry, rhs: QwengramSummarizerEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.header(lId, lSection, lText), .header(rId, rSection, rText)):
            return lId == rId && lSection == rSection && lText == rText
        case let (.input(lId, lSection, lText, lEnabled), .input(rId, rSection, rText, rEnabled)):
            return lId == rId && lSection == rSection && lText == rText && lEnabled == rEnabled
        case let (.summarize(lId, lSection, lEnabled), .summarize(rId, rSection, rEnabled)):
            return lId == rId && lSection == rSection && lEnabled == rEnabled
        case let (.loading(lId, lSection), .loading(rId, rSection)):
            return lId == rId && lSection == rSection
        case let (.result(lId, lSection, lText), .result(rId, rSection, rText)):
            return lId == rId && lSection == rSection && lText == rText
        default:
            return false
        }
    }

    static func < (lhs: QwengramSummarizerEntry, rhs: QwengramSummarizerEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! QwengramSummarizerArguments
        switch self {
        case let .header(_, section, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: section)
        case let .input(_, section, text, enabled):
            return ItemListMultilineInputItem(presentationData: presentationData, text: text, placeholder: "Paste or type text to summarize", maxLength: nil, sectionId: section, style: .blocks, textUpdated: enabled ? arguments.updateInput : { _ in })
        case let .summarize(_, section, enabled):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Summarize", kind: enabled ? .generic : .disabled, alignment: .natural, sectionId: section, style: .blocks, action: enabled ? arguments.summarize : {})
        case let .loading(_, section):
            return ItemListTextItem(presentationData: presentationData, text: .plain("Summarizing…"), sectionId: section)
        case let .result(_, section, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: section)
        }
    }
}

public func qwengramSummarizerController(context: AccountContext, initialText: String = "") -> ViewController {
    let updatePromise = ValuePromise<Int32>(0, ignoreRepeated: false)
    var updateValue: Int32 = 0
    var input = initialText
    var result: String?
    var isSummarizing = false
    weak var controller: ItemListController?
    let refresh: () -> Void = {
        updateValue += 1
        updatePromise.set(updateValue)
    }
    let showError: (String) -> Void = { text in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        controller?.present(textAlertController(context: context, title: "Summarizer", text: text, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), in: .window(.root))
    }
    let arguments = QwengramSummarizerArguments(updateInput: { value in
        input = value
    }, summarize: {
        guard QwengramSettings.shared.qwengramEnabled else {
            showError(ngI18n("Qwengram.Disabled", context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode))
            return
        }
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            showError("Enter text to summarize.")
            return
        }
        guard !isSummarizing else {
            return
        }
        let apiKey: String
        do {
            guard let storedKey = try QwengramAIKeychain.loadQwenAPIKey(), !storedKey.isEmpty else {
                showError("Configure Qwen Provider in Qwengram Settings → AI before summarizing.")
                return
            }
            apiKey = storedKey
        } catch {
            showError("Unable to access the Qwen API key. Configure Qwen Provider in Qwengram Settings → AI.")
            return
        }
        let model = QwengramSettings.shared.qwenModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            showError("Configure a Qwen model in Qwengram Settings → AI before summarizing.")
            return
        }

        isSummarizing = true
        result = nil
        refresh()
        let messages = [
            QwengramAIMessage(role: .system, content: "You summarize text accurately and concisely. Preserve important facts and do not invent information."),
            QwengramAIMessage(role: .user, content: text),
        ]
        QwengramQwenProvider(apiKey: apiKey).generateText(model: model, messages: messages) { requestResult in
            Queue.mainQueue().async {
                isSummarizing = false
                switch requestResult {
                case let .success(summary):
                    let trimmedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmedSummary.isEmpty {
                        showError("Qwen returned an empty summary. Try again.")
                    } else {
                        result = trimmedSummary
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
                        message = "Qwen returned an empty summary. Try again."
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
        var entries: [QwengramSummarizerEntry] = [
            .header(0, 0, "Text"),
            .input(1, 0, input, !isSummarizing),
            .summarize(2, 1, enabled && !isSummarizing),
        ]
        if isSummarizing {
            entries.append(.loading(3, 1))
        }
        if let result {
            entries.append(.header(4, 2, "Result"))
            entries.append(.result(5, 2, result))
        }
        let controllerState = ItemListControllerState(presentationData: listPresentationData, title: .text("Summarizer"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        return (controllerState, (ItemListNodeState(presentationData: listPresentationData, entries: entries, style: .blocks, animateChanges: true), arguments))
    }
    let itemListController = ItemListController(context: context, state: signal)
    itemListController.navigationPresentation = .default
    controller = itemListController
    return itemListController
}
