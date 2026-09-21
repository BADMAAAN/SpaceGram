import AccountContext
import Display
import ItemListUI
import PresentationDataUtils
import SpaceGramAppearance
import SpaceGramBots
import SpaceGramSettings
import SpaceGramSettingsSignal
import SpaceGramStrings
import SwiftSignalKit
import TelegramPresentationData

private final class SpaceGramBotsArguments {
    let openBot: (SpaceGramBotDescriptor) -> Void

    init(openBot: @escaping (SpaceGramBotDescriptor) -> Void) {
        self.openBot = openBot
    }
}

private enum SpaceGramBotsEntry: ItemListNodeEntry {
    case header(Int32, Int32, String)
    case bot(Int32, Int32, SpaceGramBotDescriptor, Bool)

    var section: ItemListSectionId {
        switch self { case let .header(_, section, _), let .bot(_, section, _, _): return section }
    }

    var stableId: Int32 {
        switch self { case let .header(id, _, _), let .bot(id, _, _, _): return id }
    }

    static func == (lhs: SpaceGramBotsEntry, rhs: SpaceGramBotsEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.header(lId, lSection, lText), .header(rId, rSection, rText)):
            return lId == rId && lSection == rSection && lText == rText
        case let (.bot(lId, lSection, lBot, lEnabled), .bot(rId, rSection, rBot, rEnabled)):
            return lId == rId && lSection == rSection && lBot.id == rBot.id && lBot.titleKey == rBot.titleKey && lBot.subtitleKey == rBot.subtitleKey && lBot.isEnabled == rBot.isEnabled && lEnabled == rEnabled
        default: return false
        }
    }

    static func < (lhs: SpaceGramBotsEntry, rhs: SpaceGramBotsEntry) -> Bool { lhs.stableId < rhs.stableId }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! SpaceGramBotsArguments
        switch self {
        case let .header(_, section, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: section)
        case let .bot(_, section, bot, toolsEnabled):
            let enabled = toolsEnabled && bot.isEnabled
            let lang = presentationData.strings.baseLanguageCode
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: ngI18n(bot.titleKey, lang), enabled: enabled, label: ngI18n(bot.subtitleKey, lang), sectionId: section, style: .blocks, disclosureStyle: enabled ? .arrow : .none, action: enabled ? {
                arguments.openBot(bot)
            } : nil)
        }
    }
}

public func spaceGramBotsController(context: AccountContext) -> ViewController {
    var pushControllerImpl: ((ViewController) -> Void)?
    let arguments = SpaceGramBotsArguments(openBot: { bot in
        guard SpaceGramSettings.shared.toolsEnabled else { return }
        if bot.id == "translator" {
            pushControllerImpl?(spaceGramTranslatorController(context: context))
        }
    })
    let signal = combineLatest(context.sharedContext.presentationData, spaceGramToolsEnabledSignal())
    |> deliverOnMainQueue
    |> map { presentationData, enabled -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let lang = presentationData.strings.baseLanguageCode
        var entries: [SpaceGramBotsEntry] = []
        var stableId: Int32 = 0
        for (section, category) in SpaceGramBotCategory.allCases.enumerated() {
            let title: String
            switch category { case .media: title = ngI18n("SpaceGram.Media", lang); case .utilities: title = ngI18n("SpaceGram.Utilities", lang); case .custom: title = ngI18n("SpaceGram.Custom", lang) }
            entries.append(.header(stableId, Int32(section), title))
            stableId += 1
            for bot in SpaceGramBotCatalog.defaultBots where bot.category == category {
                entries.append(.bot(stableId, Int32(section), bot, enabled))
                stableId += 1
            }
        }
        let listPresentationData = spaceGramItemListPresentationData(presentationData)
        let controllerState = ItemListControllerState(presentationData: listPresentationData, title: .text(ngI18n("SpaceGram.Tools", lang)), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        return (controllerState, (ItemListNodeState(presentationData: listPresentationData, entries: entries, style: .blocks, animateChanges: true), arguments))
    }
    let controller = ItemListController(context: context, state: signal)
    controller.navigationPresentation = .default
    pushControllerImpl = { [weak controller] viewController in
        (controller?.navigationController as? NavigationController)?.pushViewController(viewController, animated: true)
    }
    return controller
}
