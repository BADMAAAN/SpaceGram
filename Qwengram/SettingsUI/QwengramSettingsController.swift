import AccountContext
import Display
import Foundation
import ItemListUI
import QwengramStrings
import PresentationDataUtils
import QwengramSettings
import QwengramSettingsSignal
import SwiftSignalKit
import TelegramPresentationData

private enum QwengramSettingsEntry: ItemListNodeEntry {
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

    static func == (lhs: QwengramSettingsEntry, rhs: QwengramSettingsEntry) -> Bool {
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

    static func < (lhs: QwengramSettingsEntry, rhs: QwengramSettingsEntry) -> Bool {
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

private final class QwengramSettingsArguments {
    let openBotsHub: () -> Void
    let openQwenProvider: () -> Void
    let openHistorySettings: () -> Void
    let openMediaSettings: () -> Void

    init(openBotsHub: @escaping () -> Void, openQwenProvider: @escaping () -> Void, openHistorySettings: @escaping () -> Void, openMediaSettings: @escaping () -> Void) {
        self.openBotsHub = openBotsHub
        self.openQwenProvider = openQwenProvider
        self.openHistorySettings = openHistorySettings
        self.openMediaSettings = openMediaSettings
    }
}

public func qwengramSettingsController(context: AccountContext) -> ViewController {
    var pushControllerImpl: ((ViewController) -> Void)?
    let arguments = QwengramSettingsArguments(
        openBotsHub: {
            guard QwengramSettings.shared.toolsEnabled else { return }
            pushControllerImpl?(qwengramBotsController(context: context))
        },
        openQwenProvider: { pushControllerImpl?(qwengramAISettingsController(context: context)) },
        openHistorySettings: { pushControllerImpl?(qwengramHistorySettingsController(context: context)) },
        openMediaSettings: { pushControllerImpl?(qwengramMediaArchiveSettingsController(context: context)) }
    )
    let signal = combineLatest(
        context.sharedContext.presentationData,
        qwengramEnabledSignal(),
        botsHubEnabledSignal(),
        qwengramGhostSettingsSignal(),
        qwengramAutomaticReadsSettingSignal()
    )
    |> deliverOnMainQueue
    |> map { presentationData, qwengramEnabled, botsHubEnabled, ghost, suppressAutomaticReads -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let lang = presentationData.strings.baseLanguageCode
        let entries: [QwengramSettingsEntry] = [
            .header(0, 0, ngI18n("Qwengram.General", lang)),
            .toggle(1, 0, ngI18n("Qwengram.Enabled", lang), qwengramEnabled, {
                QwengramSettings.shared.qwengramEnabled = $0
            }),
            .about(2, 0, ngI18n(qwengramEnabled ? "Qwengram.Foundation" : "Qwengram.Disabled", lang)),
            .header(3, 1, ngI18n("Qwengram.Ghost", lang)),
            .toggle(4, 1, ngI18n("Qwengram.Activity", lang), ghost.0, { QwengramSettings.shared.hideChatActivity = $0 }),
            .toggle(5, 1, ngI18n("Qwengram.Stories", lang), ghost.1, { QwengramSettings.shared.hideStoryViews = $0 }),
            .toggle(6, 1, ngI18n("Qwengram.Online", lang), ghost.2, { QwengramSettings.shared.hideOnlinePresence = $0 }),
            .about(7, 1, ngI18n("Qwengram.GhostInfo", lang)),
            .header(8, 2, ngI18n("Qwengram.Privacy", lang)),
            .toggle(9, 2, ngI18n("Qwengram.AutomaticReads", lang), suppressAutomaticReads, { QwengramSettings.shared.suppressAutomaticReads = $0 }),
            .header(10, 3, ngI18n("Qwengram.History", lang)),
            .navigation(11, 3, ngI18n("Qwengram.History", lang), true, arguments.openHistorySettings),
            .header(12, 4, ngI18n("Qwengram.Archive", lang)),
            .navigation(13, 4, ngI18n("Qwengram.Archive", lang), true, arguments.openMediaSettings),
            .header(14, 5, ngI18n("Qwengram.Tools", lang)),
            .toggle(15, 5, ngI18n("Qwengram.ToolsEnabled", lang), botsHubEnabled, { QwengramSettings.shared.botsHubEnabled = $0 }),
            .navigation(16, 5, ngI18n("Qwengram.OpenTools", lang), qwengramEnabled && botsHubEnabled, arguments.openBotsHub),
            .navigation(17, 5, ngI18n("Qwengram.Provider", lang), true, arguments.openQwenProvider),
            .header(18, 6, ngI18n("Qwengram.Appearance", lang)),
            .about(19, 6, ngI18n("Qwengram.AppearanceInfo", lang)),
            .header(20, 7, ngI18n("Qwengram.Advanced", lang)),
            .about(21, 7, ngI18n("Qwengram.AdvancedInfo", lang))
        ]
        let listPresentationData = ItemListPresentationData(presentationData)
        let controllerState = ItemListControllerState(presentationData: listPresentationData, title: .text("Qwengram"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
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
