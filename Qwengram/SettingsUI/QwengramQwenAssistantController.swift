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
import TextFormat
import UIKit

private final class QwengramQwenAssistantArguments {
    let context: AccountContext
    let updateInput: (String) -> Void
    let send: () -> Void
    let stop: () -> Void
    let toggleConversations: () -> Void
    let newConversation: () -> Void
    let selectConversation: (String) -> Void
    let deleteConversation: () -> Void
    let showEarlier: () -> Void
    let updateSearch: (String) -> Void
    let toggleRename: () -> Void
    let updateRename: (String) -> Void
    let saveRename: () -> Void
    let messageActions: (String) -> Void

    init(context: AccountContext, updateInput: @escaping (String) -> Void, send: @escaping () -> Void, stop: @escaping () -> Void, toggleConversations: @escaping () -> Void, newConversation: @escaping () -> Void, selectConversation: @escaping (String) -> Void, deleteConversation: @escaping () -> Void, showEarlier: @escaping () -> Void, updateSearch: @escaping (String) -> Void, toggleRename: @escaping () -> Void, updateRename: @escaping (String) -> Void, saveRename: @escaping () -> Void, messageActions: @escaping (String) -> Void) {
        self.context = context
        self.updateInput = updateInput
        self.send = send
        self.stop = stop
        self.toggleConversations = toggleConversations
        self.newConversation = newConversation
        self.selectConversation = selectConversation
        self.deleteConversation = deleteConversation
        self.showEarlier = showEarlier
        self.updateSearch = updateSearch
        self.toggleRename = toggleRename
        self.updateRename = updateRename
        self.saveRename = saveRename
        self.messageActions = messageActions
    }
}

private enum QwengramQwenAssistantEntry: ItemListNodeEntry {
    case header(Int32, Int32, String)
    case message(Int32, Int32, QwengramAIMessage, Bool)
    case loading(Int32, Int32)
    case input(Int32, Int32, String, Bool)
    case send(Int32, Int32, Bool)
    case stop(Int32, Int32)
    case conversations(Int32, Int32, String)
    case newConversation(Int32, Int32)
    case selectConversation(Int32, Int32, String, String, String)
    case deleteConversation(Int32, Int32)
    case contextInfo(Int32, Int32, String)
    case showEarlier(Int32, Int32, String)
    case search(Int32, Int32, String)
    case rename(Int32, Int32)
    case renameInput(Int32, Int32, String)
    case saveRename(Int32, Int32)
    case messageActions(Int32, Int32, String)

    var section: ItemListSectionId {
        switch self {
        case let .header(_, section, _), let .message(_, section, _, _), let .loading(_, section), let .input(_, section, _, _), let .send(_, section, _), let .stop(_, section), let .conversations(_, section, _), let .newConversation(_, section), let .selectConversation(_, section, _, _, _), let .deleteConversation(_, section), let .contextInfo(_, section, _), let .showEarlier(_, section, _), let .search(_, section, _), let .rename(_, section), let .renameInput(_, section, _), let .saveRename(_, section), let .messageActions(_, section, _):
            return section
        }
    }

    var stableId: Int32 {
        switch self {
        case let .header(id, _, _), let .message(id, _, _, _), let .loading(id, _), let .input(id, _, _, _), let .send(id, _, _), let .stop(id, _), let .conversations(id, _, _), let .newConversation(id, _), let .selectConversation(id, _, _, _, _), let .deleteConversation(id, _), let .contextInfo(id, _, _), let .showEarlier(id, _, _), let .search(id, _, _), let .rename(id, _), let .renameInput(id, _, _), let .saveRename(id, _), let .messageActions(id, _, _):
            return id
        }
    }

    static func == (lhs: QwengramQwenAssistantEntry, rhs: QwengramQwenAssistantEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.header(lId, lSection, lText), .header(rId, rSection, rText)):
            return lId == rId && lSection == rSection && lText == rText
        case let (.message(lId, lSection, lMessage, lStreaming), .message(rId, rSection, rMessage, rStreaming)):
            return lId == rId && lSection == rSection && lMessage == rMessage && lStreaming == rStreaming
        case let (.loading(lId, lSection), .loading(rId, rSection)):
            return lId == rId && lSection == rSection
        case let (.input(lId, lSection, lText, lEnabled), .input(rId, rSection, rText, rEnabled)):
            return lId == rId && lSection == rSection && lText == rText && lEnabled == rEnabled
        case let (.send(lId, lSection, lEnabled), .send(rId, rSection, rEnabled)):
            return lId == rId && lSection == rSection && lEnabled == rEnabled
        case let (.stop(lId, lSection), .stop(rId, rSection)):
            return lId == rId && lSection == rSection
        case let (.conversations(lId, lSection, lText), .conversations(rId, rSection, rText)), let (.contextInfo(lId, lSection, lText), .contextInfo(rId, rSection, rText)):
            return lId == rId && lSection == rSection && lText == rText
        case let (.selectConversation(lId, lSection, lKey, lTitle, lPreview), .selectConversation(rId, rSection, rKey, rTitle, rPreview)):
            return lId == rId && lSection == rSection && lKey == rKey && lTitle == rTitle && lPreview == rPreview
        case let (.newConversation(lId, lSection), .newConversation(rId, rSection)), let (.deleteConversation(lId, lSection), .deleteConversation(rId, rSection)):
            return lId == rId && lSection == rSection
        case let (.showEarlier(lId, lSection, lText), .showEarlier(rId, rSection, rText)):
            return lId == rId && lSection == rSection && lText == rText
        case let (.search(lId, lSection, lText), .search(rId, rSection, rText)), let (.renameInput(lId, lSection, lText), .renameInput(rId, rSection, rText)), let (.messageActions(lId, lSection, lText), .messageActions(rId, rSection, rText)):
            return lId == rId && lSection == rSection && lText == rText
        case let (.rename(lId, lSection), .rename(rId, rSection)), let (.saveRename(lId, lSection), .saveRename(rId, rSection)):
            return lId == rId && lSection == rSection
        default:
            return false
        }
    }

    static func < (lhs: QwengramQwenAssistantEntry, rhs: QwengramQwenAssistantEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! QwengramQwenAssistantArguments
        switch self {
        case let .header(_, section, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: section)
        case let .message(_, section, message, streaming):
            let title = message.role == .user ? "You" : "Qwen"
            if message.role == .assistant && !streaming {
                return ItemListTextItem(presentationData: presentationData, text: .custom(context: arguments.context, string: qwengramRenderAIResponse("\(title): \(message.content)", color: presentationData.theme.list.freeTextColor, linkColor: presentationData.theme.list.itemAccentColor)), sectionId: section, linkAction: { action in
                    if case let .tap(value) = action, let url = URL(string: value), ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
                        UIApplication.shared.open(url)
                    }
                })
            }
            return ItemListTextItem(presentationData: presentationData, text: .plain("\(title): \(message.content)"), sectionId: section)
        case let .loading(_, section):
            return ItemListTextItem(presentationData: presentationData, text: .plain("Qwen is thinking…"), sectionId: section)
        case let .input(_, section, text, enabled):
            return ItemListMultilineInputItem(presentationData: presentationData, systemStyle: .glass, text: text, placeholder: "Ask Qwen", maxLength: ItemListMultilineInputItemTextLimit(value: QwengramConversationStore.maxContextCharacters, display: true), sectionId: section, style: .blocks, minimalHeight: 84.0, maximalHeight: 240.0, textUpdated: enabled ? arguments.updateInput : { _ in })
        case let .send(_, section, enabled):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Send", kind: enabled ? .generic : .disabled, alignment: .natural, sectionId: section, style: .blocks, action: enabled ? arguments.send : {})
        case let .stop(_, section):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Stop generating", kind: .generic, alignment: .natural, sectionId: section, style: .blocks, action: arguments.stop)
        case let .conversations(_, section, title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: section, style: .blocks, action: arguments.toggleConversations)
        case let .newConversation(_, section):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: ngI18n("Qwengram.AI.NewConversation", presentationData.strings.baseLanguageCode), kind: .generic, alignment: .natural, sectionId: section, style: .blocks, action: arguments.newConversation)
        case let .selectConversation(_, section, id, title, preview):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: preview, labelStyle: .multilineDetailText, sectionId: section, style: .blocks, action: { arguments.selectConversation(id) })
        case let .deleteConversation(_, section):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: ngI18n("Qwengram.AI.DeleteConversation", presentationData.strings.baseLanguageCode), kind: .generic, alignment: .natural, sectionId: section, style: .blocks, action: arguments.deleteConversation)
        case let .contextInfo(_, section, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: section)
        case let .showEarlier(_, section, title):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: .generic, alignment: .natural, sectionId: section, style: .blocks, action: arguments.showEarlier)
        case let .search(_, section, value):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(string: ngI18n("Qwengram.History.Search", presentationData.strings.baseLanguageCode), textColor: presentationData.theme.list.itemPrimaryTextColor), text: value, placeholder: ngI18n("Qwengram.AI.SearchPlaceholder", presentationData.strings.baseLanguageCode), type: .regular(capitalization: false, autocorrection: false), clearType: .onFocus, sectionId: section, textUpdated: arguments.updateSearch, action: {})
        case let .rename(_, section):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: ngI18n("Qwengram.AI.Rename", presentationData.strings.baseLanguageCode), kind: .generic, alignment: .natural, sectionId: section, style: .blocks, action: arguments.toggleRename)
        case let .renameInput(_, section, value):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(string: ngI18n("Qwengram.AI.Title", presentationData.strings.baseLanguageCode), textColor: presentationData.theme.list.itemPrimaryTextColor), text: value, placeholder: ngI18n("Qwengram.AI.Title", presentationData.strings.baseLanguageCode), type: .regular(capitalization: true, autocorrection: true), clearType: .onFocus, sectionId: section, textUpdated: arguments.updateRename, action: {})
        case let .saveRename(_, section):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: ngI18n("Qwengram.AI.SaveTitle", presentationData.strings.baseLanguageCode), kind: .generic, alignment: .natural, sectionId: section, style: .blocks, action: arguments.saveRename)
        case let .messageActions(_, section, id):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: ngI18n("Qwengram.AI.MessageActions", presentationData.strings.baseLanguageCode), kind: .generic, alignment: .natural, sectionId: section, style: .blocks, action: { arguments.messageActions(id) })
        }
    }
}

public func qwengramQwenAssistantController(context: AccountContext, initialText: String = "") -> ViewController {
    let store = QwengramConversationStore(mediaBoxPath: context.account.postbox.mediaBox.basePath)
    let updatePromise = ValuePromise<Int32>(0, ignoreRepeated: false)
    var updateValue: Int32 = 0
    var input = initialText
    var messages: [QwengramAIMessage] = []
    var current = QwengramAIConversation()
    var conversations: [QwengramAIConversation] = []
    var conversationsLoaded = false
    var showConversations = false
    var conversationSearch = ""
    var isRenaming = false
    var renameDraft = ""
    var messageLimit = 50
    var isSending = false
    var streamingTask: QwengramAIStreamingTask?
    var streamingGeneration = 0
    weak var controller: ItemListController?
    let refresh: () -> Void = {
        updateValue += 1
        updatePromise.set(updateValue)
    }
    let showError: (String) -> Void = { text in
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        controller?.present(textAlertController(context: context, title: "Qwen Assistant", text: text, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), in: .window(.root))
    }
    let saveConversation: () -> Void = {
        var snapshot = current
        snapshot.messages = messages.filter { $0.role != .assistant || !$0.content.isEmpty }
        guard !snapshot.messages.isEmpty else { return }
        if !snapshot.titleIsCustom {
            snapshot.title = String((snapshot.messages.first { $0.role == .user }?.content ?? "Conversation").trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        }
        snapshot.updatedAt = Date()
        current = snapshot
        conversations.removeAll { $0.id == snapshot.id }
        conversations.insert(snapshot, at: 0)
        store.save(snapshot) { result in
            if case .failure = result {
                Queue.mainQueue().async { showError("Unable to save this conversation on this device.") }
            }
        }
    }
    let stop: () -> Void = {
        guard isSending else {
            return
        }
        isSending = false
        streamingGeneration += 1
        let task = streamingTask
        streamingTask = nil
        if messages.last?.content.isEmpty == true {
            messages.removeLast()
        }
        saveConversation()
        refresh()
        task?.cancel()
    }
    let startGeneration: (String?, Int?) -> Void = { newText, userIndex in
        guard !isSending, conversationsLoaded else { return }
        guard QwengramSettings.shared.qwengramEnabled else {
            showError(ngI18n("Qwengram.Disabled", context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode))
            return
        }
        if let newText, newText.isEmpty || newText.count > QwengramConversationStore.maxContextCharacters {
            showError("This message exceeds the conversation context limit or is empty.")
            return
        }
        let apiKey: String
        do {
            guard let storedKey = try QwengramAIKeychain.loadQwenAPIKey(accountId: context.account.id.int64), !storedKey.isEmpty else {
                showError("Configure Qwen Provider in Qwengram Settings → AI before sending a message.")
                return
            }
            apiKey = storedKey
        } catch {
            showError("Unable to access the Qwen API key. Configure Qwen Provider in Qwengram Settings → AI.")
            return
        }
        let model = QwengramSettings.shared.qwenModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else {
            showError("Configure a Qwen model in Qwengram Settings → AI before sending a message.")
            return
        }
        var sourceMessages = messages
        if let userIndex {
            guard messages.indices.contains(userIndex), messages[userIndex].role == .user,
                  userIndex == messages.lastIndex(where: { $0.role == .user }) else { return }
            sourceMessages = Array(messages.prefix(userIndex + 1))
        } else if let newText {
            sourceMessages.append(QwengramAIMessage(role: .user, content: newText))
        } else { return }
        var requestConversation = current
        requestConversation.messages = sourceMessages
        let requestMessages = QwengramConversationStore.requestContext(requestConversation)
        guard requestMessages.contains(where: { $0.role == .user }) else {
            showError("The context limit cannot fit this message and system prompt.")
            return
        }
        if let newText {
            messages.append(QwengramAIMessage(role: .user, content: newText))
            input = ""
        }
        messages.append(QwengramAIMessage(role: .assistant, content: ""))
        current.model = model
        saveConversation()
        isSending = true
        streamingGeneration += 1
        let generation = streamingGeneration
        refresh()
        let provider = QwengramQwenProvider(apiKey: apiKey)
        streamingTask = provider.streamText(model: model, messages: requestMessages, onUpdate: { text in
            Queue.mainQueue().async {
                guard generation == streamingGeneration, isSending, !messages.isEmpty else { return }
                let previous = messages[messages.count - 1]
                messages[messages.count - 1] = QwengramAIMessage(role: .assistant, content: previous.content + text, id: previous.id, attachments: previous.attachments)
                refresh()
            }
        }, completion: { result in
            Queue.mainQueue().async {
                guard generation == streamingGeneration else { return }
                isSending = false
                streamingTask = nil
                switch result {
                case .success:
                    if messages.last?.content.isEmpty == true {
                        messages.removeLast()
                        showError("Qwen returned an empty response. Try again.")
                    }
                case let .failure(error):
                    if messages.last?.content.isEmpty == true { messages.removeLast() }
                    let message: String
                    switch error {
                    case .disabled: message = ngI18n("Qwengram.Disabled", context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode)
                    case .invalidRequest: message = "The Qwen request could not be created. Check the Qwen Provider settings."
                    case .network: message = "Unable to reach Qwen. Check your network connection and try again."
                    case let .httpStatus(status): message = "Qwen returned an error (HTTP \(status)). Check your Provider settings and try again."
                    case .decoding: message = "Qwen returned an unreadable response. Try again later."
                    case .emptyResponse: message = "Qwen returned an empty response. Try again."
                    case .streamEndedUnexpectedly: message = "Qwen stopped responding unexpectedly. Try again."
                    }
                    showError(message)
                }
                saveConversation()
                refresh()
            }
        })
    }
    let arguments = QwengramQwenAssistantArguments(context: context, updateInput: { value in
        input = value
    }, send: {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        startGeneration(text, nil)
    }, stop: stop, toggleConversations: {
        showConversations.toggle()
        refresh()
    }, newConversation: {
        stop()
        current = QwengramAIConversation()
        messages = []
        input = ""
        showConversations = false
        isRenaming = false
        messageLimit = 50
        refresh()
    }, selectConversation: { id in
        stop()
        guard let selected = conversations.first(where: { $0.id == id }) else { return }
        current = selected
        messages = selected.messages
        input = ""
        showConversations = false
        isRenaming = false
        messageLimit = 50
        refresh()
    }, deleteConversation: {
        let data = context.sharedContext.currentPresentationData.with { $0 }
        controller?.present(textAlertController(context: context, title: "Delete conversation?", text: "This Qwen conversation will be removed from this device.", actions: [
            TextAlertAction(type: .defaultAction, title: data.strings.Common_Cancel, action: {}),
            TextAlertAction(type: .destructiveAction, title: data.strings.Common_Delete, action: {
                stop()
                let id = current.id
                conversations.removeAll { $0.id == id }
                current = QwengramAIConversation()
                messages = []
                input = ""
                isRenaming = false
                messageLimit = 50
                refresh()
                store.remove(id: id) { result in
                    if case .failure = result { Queue.mainQueue().async { showError("Unable to delete this conversation.") } }
                }
            })
        ]), in: .window(.root))
    }, showEarlier: {
        messageLimit += 50
        refresh()
    }, updateSearch: { value in
        conversationSearch = value
        refresh()
    }, toggleRename: {
        isRenaming.toggle()
        renameDraft = current.title
        refresh()
    }, updateRename: { value in
        renameDraft = value
    }, saveRename: {
        let title = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title.count <= 80 else { showError("Enter a title of up to 80 characters."); return }
        current.title = title
        current.titleIsCustom = true
        isRenaming = false
        saveConversation()
        refresh()
    }, messageActions: { id in
        guard let index = messages.firstIndex(where: { $0.id == id }), !messages[index].content.isEmpty else { return }
        let selected = messages[index]
        let data = context.sharedContext.currentPresentationData.with { $0 }
        var actions: [TextAlertAction] = [
            TextAlertAction(type: .genericAction, title: ngI18n("Qwengram.AI.Copy", data.strings.baseLanguageCode), action: { UIPasteboard.general.string = selected.content }),
            TextAlertAction(type: .genericAction, title: ngI18n("Qwengram.AI.Share", data.strings.baseLanguageCode), action: {
                guard let controller else { return }
                let sheet = UIActivityViewController(activityItems: [selected.content], applicationActivities: nil)
                if let popover = sheet.popoverPresentationController {
                    popover.sourceView = controller.view
                    popover.sourceRect = CGRect(x: controller.view.bounds.midX, y: controller.view.bounds.midY, width: 1, height: 1)
                }
                controller.present(sheet, animated: true)
            })
        ]
        if selected.role == .user, index == messages.lastIndex(where: { $0.role == .user }) {
            actions.append(TextAlertAction(type: .genericAction, title: ngI18n("Qwengram.AI.Retry", data.strings.baseLanguageCode), action: { startGeneration(nil, index) }))
        }
        if selected.role == .assistant, index == messages.count - 1,
           let userIndex = messages.lastIndex(where: { $0.role == .user }) {
            actions.append(TextAlertAction(type: .genericAction, title: ngI18n("Qwengram.AI.Regenerate", data.strings.baseLanguageCode), action: { startGeneration(nil, userIndex) }))
        }
        actions.append(TextAlertAction(type: .destructiveAction, title: ngI18n("Qwengram.AI.DeleteMessage", data.strings.baseLanguageCode), action: {
            controller?.present(textAlertController(context: context, title: "Delete message?", text: "Only this local conversation message will be removed.", actions: [
                TextAlertAction(type: .defaultAction, title: data.strings.Common_Cancel, action: {}),
                TextAlertAction(type: .destructiveAction, title: data.strings.Common_Delete, action: {
                    stop()
                    guard let currentIndex = messages.firstIndex(where: { $0.id == id }) else { return }
                    messages.remove(at: currentIndex)
                    if messages.isEmpty {
                        let conversationId = current.id
                        conversations.removeAll { $0.id == conversationId }
                        current = QwengramAIConversation()
                        store.remove(id: conversationId) { result in
                            if case .failure = result { Queue.mainQueue().async { showError("Unable to delete this message.") } }
                        }
                    } else { saveConversation() }
                    refresh()
                })
            ]), in: .window(.root))
        }))
        actions.append(TextAlertAction(type: .defaultAction, title: data.strings.Common_Cancel, action: {}))
        controller?.present(textAlertController(context: context, title: ngI18n("Qwengram.AI.MessageActions", data.strings.baseLanguageCode), text: String(selected.content.prefix(120)), actions: actions), in: .window(.root))
    })
    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, updatePromise.get(), qwengramEnabledSignal())
    |> map { presentationData, _, enabled -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let listPresentationData = ItemListPresentationData(presentationData)
        var entries: [QwengramQwenAssistantEntry] = [.header(0, 0, current.messages.isEmpty ? ngI18n("Qwengram.AI.NewConversation", presentationData.strings.baseLanguageCode) : current.title)]
        var stableId: Int32 = 1
        entries.append(.conversations(stableId, 0, ngI18n(showConversations ? "Qwengram.AI.HideConversations" : "Qwengram.AI.Conversations", presentationData.strings.baseLanguageCode)))
        stableId += 1
        if showConversations {
            entries.append(.newConversation(stableId, 0))
            stableId += 1
            entries.append(.search(stableId, 0, conversationSearch))
            stableId += 1
            for conversation in conversations where conversationSearch.isEmpty || conversation.title.localizedCaseInsensitiveContains(conversationSearch) || conversation.messages.last?.content.localizedCaseInsensitiveContains(conversationSearch) == true {
                let updated = DateFormatter.localizedString(from: conversation.updatedAt, dateStyle: .short, timeStyle: .short)
                let preview = String((conversation.messages.last { !$0.content.isEmpty }?.content ?? "").split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").prefix(90))
                entries.append(.selectConversation(stableId, 0, conversation.id, (conversation.id == current.id ? "✓ " : "") + conversation.title + " · " + updated, preview))
                stableId += 1
            }
        }
        if !messages.isEmpty {
            entries.append(.rename(stableId, 0))
            stableId += 1
            if isRenaming {
                entries.append(.renameInput(stableId, 0, renameDraft))
                stableId += 1
                entries.append(.saveRename(stableId, 0))
                stableId += 1
            }
            entries.append(.deleteConversation(stableId, 0))
            stableId += 1
        }
        if messages.count > messageLimit {
            entries.append(.showEarlier(stableId, 0, ngI18n("Qwengram.AI.ShowEarlier", presentationData.strings.baseLanguageCode) + " (\(messages.count - messageLimit))"))
            stableId += 1
        }
        for message in messages.suffix(messageLimit) {
            entries.append(.message(stableId, 0, message, isSending && message.id == messages.last?.id))
            stableId += 1
            if !message.content.isEmpty {
                entries.append(.messageActions(stableId, 0, message.id))
                stableId += 1
            }
        }
        if isSending {
            entries.append(.loading(stableId, 0))
            stableId += 1
        }
        if !messages.isEmpty {
            let completedMessages = messages.filter { !$0.content.isEmpty }
            var contextConversation = current
            contextConversation.messages = completedMessages
            let count = QwengramConversationStore.requestContext(contextConversation).filter { $0.role != .system }.count
            entries.append(.contextInfo(stableId, 0, "Qwen uses the most recent \(count) of \(completedMessages.count) messages as context."))
            stableId += 1
        }
        entries.append(.header(stableId, 1, "Message"))
        stableId += 1
        entries.append(.input(stableId, 1, input, !isSending))
        stableId += 1
        if !conversationsLoaded {
            entries.append(.contextInfo(stableId, 2, "Loading saved conversations…"))
        } else if isSending {
            entries.append(.stop(stableId, 2))
        } else {
            entries.append(.send(stableId, 2, enabled))
        }
        let controllerState = ItemListControllerState(presentationData: listPresentationData, title: .text("Qwen Assistant"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        return (controllerState, (ItemListNodeState(presentationData: listPresentationData, entries: entries, style: .blocks, animateChanges: true), arguments))
    }
    let itemListController = ItemListController(context: context, state: signal)
    itemListController.navigationPresentation = .default
    itemListController.didDisappear = { _ in
        stop()
    }
    controller = itemListController
    store.list { result in
        Queue.mainQueue().async {
            switch result {
            case let .success(saved):
                conversations = saved
                if let latest = saved.first {
                    current = latest
                    messages = latest.messages
                }
            case .failure:
                showError("Unable to load saved Qwen conversations. New messages will be saved if storage becomes available.")
            }
            conversationsLoaded = true
            refresh()
        }
    }
    return itemListController
}
