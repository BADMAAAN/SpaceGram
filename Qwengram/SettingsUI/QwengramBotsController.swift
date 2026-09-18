import AccountContext
import Display
import ItemListUI
import QwengramStrings
import PresentationDataUtils
import QwengramBots
import QwengramSettings
import QwengramSettingsSignal
import SwiftSignalKit
import TelegramPresentationData

private final class QwengramBotsArguments {
    let openBot: (QwengramBotDescriptor) -> Void

    init(openBot: @escaping (QwengramBotDescriptor) -> Void) {
        self.openBot = openBot
    }
}

private enum QwengramBotsEntry: ItemListNodeEntry {
    case header(Int32, Int32, String)
    case bot(Int32, Int32, QwengramBotDescriptor, Bool)

    var section: ItemListSectionId {
        switch self { case let .header(_, section, _), let .bot(_, section, _, _): return section }
    }

    var stableId: Int32 {
        switch self { case let .header(id, _, _), let .bot(id, _, _, _): return id }
    }

    static func == (lhs: QwengramBotsEntry, rhs: QwengramBotsEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.header(lId, lSection, lText), .header(rId, rSection, rText)):
            return lId == rId && lSection == rSection && lText == rText
        case let (.bot(lId, lSection, lBot, lEnabled), .bot(rId, rSection, rBot, rEnabled)):
            return lId == rId && lSection == rSection && lBot.id == rBot.id && lBot.title == rBot.title && lBot.subtitle == rBot.subtitle && lBot.isEnabled == rBot.isEnabled && lEnabled == rEnabled
        default: return false
        }
    }

    static func < (lhs: QwengramBotsEntry, rhs: QwengramBotsEntry) -> Bool { lhs.stableId < rhs.stableId }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! QwengramBotsArguments
        switch self {
        case let .header(_, section, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: section)
        case let .bot(_, section, bot, toolsEnabled):
            let enabled = toolsEnabled && bot.isEnabled
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: bot.title, enabled: enabled, label: bot.subtitle, sectionId: section, style: .blocks, disclosureStyle: enabled ? .arrow : .none, action: enabled ? {
                arguments.openBot(bot)
            } : nil)
        }
    }
}

public func qwengramBotsController(context: AccountContext) -> ViewController {
    var pushControllerImpl: ((ViewController) -> Void)?
    let arguments = QwengramBotsArguments(openBot: { bot in
        guard QwengramSettings.shared.toolsEnabled else { return }
        if bot.id == "qwen-assistant" {
            pushControllerImpl?(qwengramQwenAssistantController(context: context))
        } else if bot.id == "summarizer" {
            pushControllerImpl?(qwengramSummarizerController(context: context))
        } else if bot.id == "translator" {
            pushControllerImpl?(qwengramTranslatorController(context: context))
        } else if bot.id == "qr-tools" {
            pushControllerImpl?(qwengramQRToolsController(context: context))
        }
    })
    let signal = combineLatest(context.sharedContext.presentationData, qwengramToolsEnabledSignal())
    |> deliverOnMainQueue
    |> map { presentationData, enabled -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let lang = presentationData.strings.baseLanguageCode
        var entries: [QwengramBotsEntry] = []
        var stableId: Int32 = 0
        for (section, category) in QwengramBotCategory.allCases.enumerated() {
            let title: String
            switch category { case .ai: title = ngI18n("Qwengram.AI", lang); case .media: title = ngI18n("Qwengram.Media", lang); case .utilities: title = ngI18n("Qwengram.Utilities", lang); case .custom: title = ngI18n("Qwengram.Custom", lang) }
            entries.append(.header(stableId, Int32(section), title))
            stableId += 1
            for bot in QwengramBotCatalog.defaultBots where bot.category == category {
                entries.append(.bot(stableId, Int32(section), bot, enabled))
                stableId += 1
            }
        }
        let listPresentationData = ItemListPresentationData(presentationData)
        let controllerState = ItemListControllerState(presentationData: listPresentationData, title: .text(ngI18n("Qwengram.Tools", lang)), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        return (controllerState, (ItemListNodeState(presentationData: listPresentationData, entries: entries, style: .blocks, animateChanges: true), arguments))
    }
    let controller = ItemListController(context: context, state: signal)
    controller.navigationPresentation = .default
    pushControllerImpl = { [weak controller] viewController in
        (controller?.navigationController as? NavigationController)?.pushViewController(viewController, animated: true)
    }
    return controller
}
