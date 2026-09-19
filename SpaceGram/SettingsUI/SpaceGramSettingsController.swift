import AccountContext
import Display
import Foundation
import ItemListUI
import PresentationDataUtils
import SpaceGramAppearance
import SpaceGramSettings
import SpaceGramSettingsSignal
import SpaceGramStrings
import SettingsUI
import SwiftSignalKit
import TelegramPresentationData

private enum SpaceGramSettingsEntry: ItemListNodeEntry {
    case header(Int32, Int32, String)
    case toggle(Int32, Int32, String, Bool, (Bool) -> Void)
    case navigation(Int32, Int32, String, Bool, () -> Void)
    case placeholder(Int32, Int32, String, String)
    case about(Int32, Int32, String)

    var section: ItemListSectionId {
        switch self {
        case let .header(_, section, _), let .toggle(_, section, _, _, _), let .navigation(_, section, _, _, _), let .placeholder(_, section, _, _), let .about(_, section, _):
            return section
        }
    }

    var stableId: Int32 {
        switch self {
        case let .header(id, _, _), let .toggle(id, _, _, _, _), let .navigation(id, _, _, _, _), let .placeholder(id, _, _, _), let .about(id, _, _):
            return id
        }
    }

    static func == (lhs: SpaceGramSettingsEntry, rhs: SpaceGramSettingsEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.header(lId, lSection, lText), .header(rId, rSection, rText)):
            return lId == rId && lSection == rSection && lText == rText
        case let (.toggle(lId, lSection, lTitle, lValue, _), .toggle(rId, rSection, rTitle, rValue, _)):
            return lId == rId && lSection == rSection && lTitle == rTitle && lValue == rValue
        case let (.navigation(lId, lSection, lTitle, lEnabled, _), .navigation(rId, rSection, rTitle, rEnabled, _)):
            return lId == rId && lSection == rSection && lTitle == rTitle && lEnabled == rEnabled
        case let (.placeholder(lId, lSection, lTitle, lLabel), .placeholder(rId, rSection, rTitle, rLabel)):
            return lId == rId && lSection == rSection && lTitle == rTitle && lLabel == rLabel
        case let (.about(lId, lSection, lText), .about(rId, rSection, rText)):
            return lId == rId && lSection == rSection && lText == rText
        default:
            return false
        }
    }

    static func < (lhs: SpaceGramSettingsEntry, rhs: SpaceGramSettingsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        switch self {
        case let .header(_, section, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: section)
        case let .toggle(_, section, title, value, updated):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: section, style: .blocks, updated: updated)
        case let .navigation(_, section, title, enabled, action):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, enabled: enabled, label: "", sectionId: section, style: .blocks, action: action)
        case let .placeholder(_, section, title, label):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, enabled: false, label: label, sectionId: section, style: .blocks, disclosureStyle: .none, action: nil)
        case let .about(_, section, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: section)
        }
    }
}

private final class SpaceGramSettingsArguments {
    let openBotsHub: () -> Void
    let openQwenProvider: () -> Void
    let openPrivacySettings: () -> Void
    let openHistorySettings: () -> Void
    let openMediaSettings: () -> Void
    let openAppearance: () -> Void

    init(openBotsHub: @escaping () -> Void, openQwenProvider: @escaping () -> Void, openPrivacySettings: @escaping () -> Void, openHistorySettings: @escaping () -> Void, openMediaSettings: @escaping () -> Void, openAppearance: @escaping () -> Void) {
        self.openBotsHub = openBotsHub
        self.openQwenProvider = openQwenProvider
        self.openPrivacySettings = openPrivacySettings
        self.openHistorySettings = openHistorySettings
        self.openMediaSettings = openMediaSettings
        self.openAppearance = openAppearance
    }
}

public func spaceGramSettingsController(context: AccountContext) -> ViewController {
    var pushControllerImpl: ((ViewController) -> Void)?
    let arguments = SpaceGramSettingsArguments(
        openBotsHub: {
            guard SpaceGramSettings.shared.toolsEnabled else { return }
            pushControllerImpl?(spaceGramBotsController(context: context))
        },
        openQwenProvider: { pushControllerImpl?(spaceGramAISettingsController(context: context)) },
        openPrivacySettings: { pushControllerImpl?(spaceGramPrivacySettingsController(context: context)) },
        openHistorySettings: { pushControllerImpl?(spaceGramHistorySettingsController(context: context)) },
        openMediaSettings: { pushControllerImpl?(spaceGramMediaArchiveSettingsController(context: context)) },
        openAppearance: { pushControllerImpl?(themeSettingsController(context: context)) }
    )
    let signal = combineLatest(
        context.sharedContext.presentationData,
        spaceGramEnabledSignal(),
        botsHubEnabledSignal(),
        spaceGramGhostSettingsSignal(),
        spaceGramAutomaticReadsSettingSignal()
    )
    |> deliverOnMainQueue
    |> map { presentationData, spaceGramEnabled, botsHubEnabled, ghost, suppressAutomaticReads -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let lang = presentationData.strings.baseLanguageCode
        let entries: [SpaceGramSettingsEntry] = [
            .header(0, 0, ngI18n("SpaceGram.General", lang)),
            .toggle(1, 0, ngI18n("SpaceGram.Enabled", lang), spaceGramEnabled, {
                SpaceGramSettings.shared.spaceGramEnabled = $0
            }),
            .about(2, 0, ngI18n(spaceGramEnabled ? "SpaceGram.Foundation" : "SpaceGram.Disabled", lang)),
            .header(3, 1, ngI18n("SpaceGram.Ghost", lang)),
            .toggle(4, 1, ngI18n("SpaceGram.Activity", lang), ghost.0, { SpaceGramSettings.shared.hideChatActivity = $0 }),
            .toggle(5, 1, ngI18n("SpaceGram.Stories", lang), ghost.1, { SpaceGramSettings.shared.hideStoryViews = $0 }),
            .toggle(6, 1, ngI18n("SpaceGram.Online", lang), ghost.2, { SpaceGramSettings.shared.hideOnlinePresence = $0 }),
            .about(7, 1, ngI18n("SpaceGram.GhostInfo", lang)),
            .header(8, 2, ngI18n("SpaceGram.Privacy", lang)),
            .toggle(9, 2, ngI18n("SpaceGram.AutomaticReads", lang), suppressAutomaticReads, { SpaceGramSettings.shared.suppressAutomaticReads = $0 }),
            .navigation(22, 2, ngI18n("SpaceGram.Privacy.Open", lang), true, arguments.openPrivacySettings),
            .header(10, 3, ngI18n("SpaceGram.History", lang)),
            .navigation(11, 3, ngI18n("SpaceGram.History", lang), true, arguments.openHistorySettings),
            .header(12, 4, ngI18n("SpaceGram.Archive", lang)),
            .navigation(13, 4, ngI18n("SpaceGram.Archive", lang), true, arguments.openMediaSettings),
            .header(14, 5, ngI18n("SpaceGram.Tools", lang)),
            .toggle(15, 5, ngI18n("SpaceGram.ToolsEnabled", lang), botsHubEnabled, { SpaceGramSettings.shared.botsHubEnabled = $0 }),
            .navigation(16, 5, ngI18n("SpaceGram.OpenTools", lang), spaceGramEnabled && botsHubEnabled, arguments.openBotsHub),
            .navigation(17, 5, ngI18n("SpaceGram.Provider", lang), true, arguments.openQwenProvider),
            .header(18, 6, ngI18n("SpaceGram.Appearance", lang)),
            .about(19, 6, ngI18n("SpaceGram.AppearanceInfo", lang)),
            .navigation(23, 6, ngI18n("SpaceGram.AppearanceTelegramThemes", lang), true, arguments.openAppearance),
            .header(20, 7, ngI18n("SpaceGram.Advanced", lang)),
            .about(21, 7, ngI18n("SpaceGram.AdvancedInfo", lang))
        ]
        let listPresentationData = spaceGramItemListPresentationData(presentationData)
        let controllerState = ItemListControllerState(presentationData: listPresentationData, title: .text("SpaceGram"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: listPresentationData, entries: entries, style: .blocks, animateChanges: true)
        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(context: context, state: signal)
    controller.navigationPresentation = .default
    pushControllerImpl = { [weak controller] viewController in
        (controller?.navigationController as? NavigationController)?.pushViewController(viewController, animated: true)
    }
    return controller
}
