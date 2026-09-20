import AccountContext
import Display
import ItemListUI
import SpaceGramSettings
import SpaceGramSettingsSignal
import SpaceGramStrings
import SwiftSignalKit
import TelegramPresentationData

private enum SpaceGramMessageMenuEntry: ItemListNodeEntry {
    case header(String)
    case action(Int, SpaceGramMessageAction, String, Bool)
    case unavailable(Int, String, String)
    case footer(String)

    var section: ItemListSectionId {
        switch self {
        case .header, .action:
            return 0
        case .unavailable, .footer:
            return 1
        }
    }

    var stableId: Int32 {
        switch self {
        case .header:
            return 0
        case let .action(index, _, _, _):
            return Int32(index + 1)
        case let .unavailable(index, _, _):
            return Int32(100 + index)
        case .footer:
            return 200
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case let (.header(lhsText), .header(rhsText)), let (.footer(lhsText), .footer(rhsText)):
            return lhsText == rhsText
        case let (.action(lhsIndex, lhsAction, lhsTitle, lhsValue), .action(rhsIndex, rhsAction, rhsTitle, rhsValue)):
            return lhsIndex == rhsIndex && lhsAction == rhsAction && lhsTitle == rhsTitle && lhsValue == rhsValue
        case let (.unavailable(lhsIndex, lhsTitle, lhsDetail), .unavailable(rhsIndex, rhsTitle, rhsDetail)):
            return lhsIndex == rhsIndex && lhsTitle == rhsTitle && lhsDetail == rhsDetail
        default:
            return false
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        switch self {
        case let .header(text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .action(_, action, title, value):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: self.section, style: .blocks, updated: { enabled in
                SpaceGramSettings.shared.setMessageActionEnabled(action, enabled: enabled)
            })
        case let .unavailable(_, title, detail):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, enabled: false, label: detail, sectionId: self.section, style: .blocks, action: nil)
        case let .footer(text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

public func spaceGramMessageMenuSettingsController(context: AccountContext) -> ViewController {
    let signal = combineLatest(context.sharedContext.presentationData, spaceGramSettingsChangesSignal())
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let language = presentationData.strings.baseLanguageCode
        var entries: [SpaceGramMessageMenuEntry] = [
            .header(ngI18n("SpaceGram.MessageMenu.Header", language))
        ]
        for (index, action) in SpaceGramMessageAction.allCases.enumerated() {
            let title = ngI18n(action.titleKey, language)
            if action.isImplemented {
                entries.append(.action(index, action, title, SpaceGramSettings.shared.isMessageActionEnabled(action)))
            } else {
                entries.append(.unavailable(index, title, ngI18n("SpaceGram.MessageMenu.NotImplemented", language)))
            }
        }
        entries.append(.footer(ngI18n("SpaceGram.MessageMenu.Footer", language)))
        let listData = spaceGramItemListPresentationData(presentationData)
        let state = ItemListControllerState(presentationData: listData, title: .text(ngI18n("SpaceGram.MessageMenu.Title", language)), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        return (state, (ItemListNodeState(presentationData: listData, entries: entries, style: .blocks, animateChanges: true), ()))
    }
    let controller = ItemListController(context: context, state: signal)
    controller.navigationPresentation = .default
    return controller
}
