import AccountContext
import Display
import Foundation
import ItemListUI
import QwengramStrings
import PresentationDataUtils
import QwengramHistoryUI
import QwengramSettings
import QwengramSettingsSignal
import SwiftSignalKit
import TelegramPresentationData

private struct QwengramHistorySettingsEntry: ItemListNodeEntry {
    let stableId: Int32
    let title: String
    var value: Bool = false
    var updated: (Bool) -> Void = { _ in }
    var action: (() -> Void)? = nil

    var section: ItemListSectionId {
        return stableId == 0 ? 0 : (stableId == 3 ? 2 : 1)
    }

    static func == (lhs: QwengramHistorySettingsEntry, rhs: QwengramHistorySettingsEntry) -> Bool {
        return lhs.stableId == rhs.stableId && lhs.title == rhs.title && lhs.value == rhs.value
    }

    static func < (lhs: QwengramHistorySettingsEntry, rhs: QwengramHistorySettingsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        if let action = action {
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: "", sectionId: section, style: .blocks, action: action)
        }
        return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: section, style: .blocks, updated: updated)
    }
}

public func qwengramHistorySettingsController(context: AccountContext) -> ViewController {
    var pushControllerImpl: ((ViewController) -> Void)?
    let signal = combineLatest(context.sharedContext.presentationData, qwengramHistorySettingsSignal())
    |> deliverOnMainQueue
    |> map { presentationData, settings -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let lang = presentationData.strings.baseLanguageCode
        let entries: [QwengramHistorySettingsEntry] = [
            QwengramHistorySettingsEntry(stableId: 0, title: ngI18n("Qwengram.History", lang), value: settings.0, updated: {
                QwengramSettings.shared.messageHistoryEnabled = $0
            }),
            QwengramHistorySettingsEntry(stableId: 1, title: ngI18n("Qwengram.SaveEdits", lang), value: settings.1, updated: {
                QwengramSettings.shared.saveEditedMessages = $0
            }),
            QwengramHistorySettingsEntry(stableId: 2, title: ngI18n("Qwengram.SaveDeletes", lang), value: settings.2, updated: {
                QwengramSettings.shared.saveServerDeletedMessages = $0
            }),
            QwengramHistorySettingsEntry(stableId: 3, title: ngI18n("Qwengram.ViewHistory", lang), action: {
                pushControllerImpl?(qwengramHistoryController(context: context))
            })
        ]
        let listPresentationData = ItemListPresentationData(presentationData)
        let controllerState = ItemListControllerState(presentationData: listPresentationData, title: .text(ngI18n("Qwengram.HistorySettings", lang)), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
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
