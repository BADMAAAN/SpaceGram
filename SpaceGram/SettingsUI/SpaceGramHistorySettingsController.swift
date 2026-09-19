import AccountContext
import Display
import Foundation
import ItemListUI
import PresentationDataUtils
import SpaceGramAppearance
import SpaceGramHistoryUI
import SpaceGramSettings
import SpaceGramSettingsSignal
import SpaceGramStrings
import SwiftSignalKit
import TelegramPresentationData

private struct SpaceGramHistorySettingsEntry: ItemListNodeEntry {
    let stableId: Int32
    let title: String
    var value: Bool = false
    var updated: (Bool) -> Void = { _ in }
    var action: (() -> Void)? = nil

    var section: ItemListSectionId {
        return stableId <= 2 ? 0 : (stableId <= 5 ? 1 : 2)
    }

    static func == (lhs: SpaceGramHistorySettingsEntry, rhs: SpaceGramHistorySettingsEntry) -> Bool {
        return lhs.stableId == rhs.stableId && lhs.title == rhs.title && lhs.value == rhs.value
    }

    static func < (lhs: SpaceGramHistorySettingsEntry, rhs: SpaceGramHistorySettingsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        if let action = action {
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: "", sectionId: section, style: .blocks, action: action)
        }
        return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: section, style: .blocks, updated: updated)
    }
}

public func spaceGramHistorySettingsController(context: AccountContext) -> ViewController {
    var pushControllerImpl: ((ViewController) -> Void)?
    let signal = combineLatest(context.sharedContext.presentationData, spaceGramHistorySettingsSignal(), spaceGramHistoryIndicatorSettingsSignal())
    |> deliverOnMainQueue
    |> map { presentationData, settings, indicators -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let lang = presentationData.strings.baseLanguageCode
        let entries: [SpaceGramHistorySettingsEntry] = [
            SpaceGramHistorySettingsEntry(stableId: 0, title: ngI18n("SpaceGram.History", lang), value: settings.0, updated: {
                SpaceGramSettings.shared.messageHistoryEnabled = $0
            }),
            SpaceGramHistorySettingsEntry(stableId: 1, title: ngI18n("SpaceGram.SaveEdits", lang), value: settings.1, updated: {
                SpaceGramSettings.shared.saveEditedMessages = $0
            }),
            SpaceGramHistorySettingsEntry(stableId: 2, title: ngI18n("SpaceGram.SaveDeletes", lang), value: settings.2, updated: {
                SpaceGramSettings.shared.saveServerDeletedMessages = $0
            }),
            SpaceGramHistorySettingsEntry(stableId: 3, title: ngI18n("SpaceGram.History.ShowIndicator", lang), value: indicators.0, updated: { SpaceGramSettings.shared.showHistoryIndicator = $0 }),
            SpaceGramHistorySettingsEntry(stableId: 4, title: ngI18n("SpaceGram.History.ShowEdited", lang), value: indicators.1, updated: { SpaceGramSettings.shared.showEditedIndicator = $0 }),
            SpaceGramHistorySettingsEntry(stableId: 5, title: ngI18n("SpaceGram.History.ShowDeleted", lang), value: indicators.2, updated: { SpaceGramSettings.shared.showDeletedIndicator = $0 }),
            SpaceGramHistorySettingsEntry(stableId: 6, title: ngI18n("SpaceGram.ViewHistory", lang), action: {
                pushControllerImpl?(spaceGramHistoryController(context: context))
            })
        ]
        let listPresentationData = spaceGramItemListPresentationData(presentationData)
        let controllerState = ItemListControllerState(presentationData: listPresentationData, title: .text(ngI18n("SpaceGram.HistorySettings", lang)), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(presentationData: listPresentationData, entries: entries, style: .blocks, animateChanges: true)
        return (controllerState, (listState, ()))
    }
    let controller = ItemListController(context: context, state: signal)
    controller.navigationPresentation = .default
    pushControllerImpl = { [weak controller] viewController in
        (controller?.navigationController as? NavigationController)?.pushViewController(viewController, animated: true)
    }
    return controller
}
