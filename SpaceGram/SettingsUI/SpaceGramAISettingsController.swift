import AccountContext
import Display
import Foundation
import ItemListUI
import PresentationDataUtils
import SpaceGramAI
import SpaceGramAppearance
import SpaceGramSettings
import SpaceGramStrings
import SwiftSignalKit
import TelegramPresentationData

private enum SpaceGramAISettingsEntry: ItemListNodeEntry {
    case header(Int32, Int32, String)
    case apiKey(Int32, Int32, String)
    case model(Int32, Int32, String)
    case status(Int32, Int32, String)
    case save(Int32, Int32)
    case removeKey(Int32, Int32)
    case context(Int32, Int32, Int)

    var section: ItemListSectionId {
        switch self {
        case let .header(_, section, _), let .apiKey(_, section, _), let .model(_, section, _), let .status(_, section, _), let .save(_, section), let .removeKey(_, section), let .context(_, section, _): return section
        }
    }

    var stableId: Int32 {
        switch self {
        case let .header(id, _, _), let .apiKey(id, _, _), let .model(id, _, _), let .status(id, _, _), let .save(id, _), let .removeKey(id, _), let .context(id, _, _): return id
        }
    }

    static func == (lhs: SpaceGramAISettingsEntry, rhs: SpaceGramAISettingsEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.context(lId, lSection, lValue), .context(rId, rSection, rValue)):
            return lId == rId && lSection == rSection && lValue == rValue
        case let (.header(lId, lSection, lText), .header(rId, rSection, rText)), let (.apiKey(lId, lSection, lText), .apiKey(rId, rSection, rText)), let (.model(lId, lSection, lText), .model(rId, rSection, rText)), let (.status(lId, lSection, lText), .status(rId, rSection, rText)):
            return lId == rId && lSection == rSection && lText == rText
        case let (.save(lId, lSection), .save(rId, rSection)), let (.removeKey(lId, lSection), .removeKey(rId, rSection)):
            return lId == rId && lSection == rSection
        default: return false
        }
    }

    static func < (lhs: SpaceGramAISettingsEntry, rhs: SpaceGramAISettingsEntry) -> Bool { lhs.stableId < rhs.stableId }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! SpaceGramAISettingsArguments
        switch self {
        case let .header(_, section, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: section)
        case let .apiKey(_, section, text):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(string: ngI18n("SpaceGram.UI.APIKey", presentationData.strings.baseLanguageCode), textColor: presentationData.theme.list.itemPrimaryTextColor), text: text, placeholder: ngI18n("SpaceGram.UI.EnterAPIKey", presentationData.strings.baseLanguageCode), type: .password, clearType: .onFocus, sectionId: section, textUpdated: arguments.updateAPIKey, action: {})
        case let .model(_, section, text):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(string: ngI18n("SpaceGram.UI.Model", presentationData.strings.baseLanguageCode), textColor: presentationData.theme.list.itemPrimaryTextColor), text: text, placeholder: ngI18n("SpaceGram.UI.ModelIdentifier", presentationData.strings.baseLanguageCode), type: .regular(capitalization: false, autocorrection: false), clearType: .onFocus, sectionId: section, textUpdated: arguments.updateModel, action: {})
        case let .status(_, section, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: section)
        case let .save(_, section):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: ngI18n("SpaceGram.UI.Save", presentationData.strings.baseLanguageCode), kind: .generic, alignment: .natural, sectionId: section, style: .blocks, action: arguments.save)
        case let .removeKey(_, section):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: ngI18n("SpaceGram.UI.RemoveKey", presentationData.strings.baseLanguageCode), kind: .destructive, alignment: .natural, sectionId: section, style: .blocks, action: arguments.removeAPIKey)
        case let .context(_, section, value):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: ngI18n("SpaceGram.AI.ContextLimit", presentationData.strings.baseLanguageCode), label: String(value), sectionId: section, style: .blocks, action: arguments.cycleContext)
        }
    }
}

private final class SpaceGramAISettingsArguments {
    let updateAPIKey: (String) -> Void
    let updateModel: (String) -> Void
    let save: () -> Void
    let removeAPIKey: () -> Void
    let cycleContext: () -> Void

    init(updateAPIKey: @escaping (String) -> Void, updateModel: @escaping (String) -> Void, save: @escaping () -> Void, removeAPIKey: @escaping () -> Void, cycleContext: @escaping () -> Void) {
        self.updateAPIKey = updateAPIKey
        self.updateModel = updateModel
        self.save = save
        self.removeAPIKey = removeAPIKey
        self.cycleContext = cycleContext
    }
}

public func spaceGramAISettingsController(context: AccountContext) -> ViewController {
    let accountId = context.account.id.int64
    let updatePromise = ValuePromise<Int32>(0, ignoreRepeated: false)
    var updateValue: Int32 = 0
    var apiKey = ""
    var model = SpaceGramSettings.shared.qwenModel
    var isConfigured = (try? SpaceGramAIKeychain.loadQwenAPIKey(accountId: accountId)) != nil
    var controller: ItemListController?
    let refresh: () -> Void = {
        updateValue += 1
        updatePromise.set(updateValue)
    }
    let showError: () -> Void = {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        controller?.present(textAlertController(context: context, title: "Qwen", text: ngI18n("SpaceGram.UI.KeyError", presentationData.strings.baseLanguageCode), actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), in: .window(.root))
    }
    let arguments = SpaceGramAISettingsArguments(updateAPIKey: { apiKey = $0 }, updateModel: { model = $0 }, save: {
        guard !model.isEmpty else {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            controller?.present(textAlertController(context: context, title: "Qwen", text: ngI18n("SpaceGram.UI.ModelError", presentationData.strings.baseLanguageCode), actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), in: .window(.root))
            return
        }
        do {
            if !apiKey.isEmpty {
                try SpaceGramAIKeychain.saveQwenAPIKey(apiKey, accountId: accountId)
                apiKey = ""
            }
            SpaceGramSettings.shared.qwenModel = model
            isConfigured = (try SpaceGramAIKeychain.loadQwenAPIKey(accountId: accountId)) != nil
            refresh()
        } catch {
            showError()
        }
    }, removeAPIKey: {
        do {
            try SpaceGramAIKeychain.deleteQwenAPIKey(accountId: accountId)
            apiKey = ""
            isConfigured = false
            refresh()
        } catch {
            showError()
        }
    }, cycleContext: {
        let presets = SpaceGramSettings.aiContextPresets
        let current = SpaceGramSettings.shared.aiContextCharacters
        let index = presets.firstIndex(of: current) ?? 2
        SpaceGramSettings.shared.aiContextCharacters = presets[(index + 1) % presets.count]
        refresh()
    })
    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, updatePromise.get())
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let listPresentationData = spaceGramItemListPresentationData(presentationData)
        let entries: [SpaceGramAISettingsEntry] = [
            .header(0, 0, "Qwen"),
            .apiKey(1, 0, apiKey),
            .model(2, 0, model),
            .header(3, 1, ngI18n("SpaceGram.UI.Status", presentationData.strings.baseLanguageCode)),
            .status(4, 1, isConfigured ? ngI18n("SpaceGram.UI.Configured", presentationData.strings.baseLanguageCode) : ngI18n("SpaceGram.UI.NotConfigured", presentationData.strings.baseLanguageCode)),
            .save(5, 2),
            .removeKey(6, 2),
            .context(7, 3, SpaceGramSettings.shared.aiContextCharacters),
            .status(8, 3, ngI18n("SpaceGram.AI.ContextHelp", presentationData.strings.baseLanguageCode)),
        ]
        let controllerState = ItemListControllerState(presentationData: listPresentationData, title: .text(ngI18n("SpaceGram.UI.Provider", presentationData.strings.baseLanguageCode)), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        return (controllerState, (ItemListNodeState(presentationData: listPresentationData, entries: entries, style: .blocks, animateChanges: true), arguments))
    }
    let itemListController = ItemListController(context: context, state: signal)
    itemListController.navigationPresentation = .default
    controller = itemListController
    return itemListController
}
