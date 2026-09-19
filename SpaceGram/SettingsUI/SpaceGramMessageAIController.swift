import AccountContext
import Display
import ItemListUI
import PresentationDataUtils
import SpaceGramAppearance
import SwiftSignalKit
import TelegramPresentationData

private final class SpaceGramMessageAIArguments {
    let openAssistant: () -> Void
    let openSummarizer: () -> Void
    let openTranslator: () -> Void

    init(openAssistant: @escaping () -> Void, openSummarizer: @escaping () -> Void, openTranslator: @escaping () -> Void) {
        self.openAssistant = openAssistant
        self.openSummarizer = openSummarizer
        self.openTranslator = openTranslator
    }
}

private enum SpaceGramMessageAIEntry: ItemListNodeEntry {
    case header(Int32, Int32, String)
    case selectedText(Int32, Int32, String)
    case action(Int32, Int32, String, () -> Void)
    case privacy(Int32, Int32, String)

    var section: ItemListSectionId {
        switch self {
        case let .header(_, section, _), let .selectedText(_, section, _), let .action(_, section, _, _), let .privacy(_, section, _):
            return section
        }
    }

    var stableId: Int32 {
        switch self {
        case let .header(id, _, _), let .selectedText(id, _, _), let .action(id, _, _, _), let .privacy(id, _, _):
            return id
        }
    }

    static func == (lhs: SpaceGramMessageAIEntry, rhs: SpaceGramMessageAIEntry) -> Bool {
        return lhs.stableId == rhs.stableId
    }

    static func < (lhs: SpaceGramMessageAIEntry, rhs: SpaceGramMessageAIEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        switch self {
        case let .header(_, section, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: section)
        case let .selectedText(_, section, text), let .privacy(_, section, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: section)
        case let .action(_, section, title, action):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: "", sectionId: section, style: .blocks, action: action)
        }
    }
}

public func spaceGramMessageAIController(context: AccountContext, text: String) -> ViewController {
    var pushControllerImpl: ((ViewController) -> Void)?
    let arguments = SpaceGramMessageAIArguments(
        openAssistant: {
            pushControllerImpl?(spaceGramQwenAssistantController(context: context, initialText: text))
        },
        openSummarizer: {
            pushControllerImpl?(spaceGramSummarizerController(context: context, initialText: text))
        },
        openTranslator: {
            pushControllerImpl?(spaceGramTranslatorController(context: context, initialText: text))
        }
    )
    let signal = context.sharedContext.presentationData
    |> map { presentationData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let listPresentationData = spaceGramItemListPresentationData(presentationData)
        let entries: [SpaceGramMessageAIEntry] = [
            .header(0, 0, "Selected Text"),
            .selectedText(1, 0, text),
            .header(2, 1, "Actions"),
            .action(3, 1, "Ask Qwen", arguments.openAssistant),
            .action(4, 1, "Summarize", arguments.openSummarizer),
            .action(5, 1, "Translate", arguments.openTranslator),
            .privacy(6, 2, "Message text stays on this device until you explicitly send it to the configured AI provider."),
        ]
        let controllerState = ItemListControllerState(presentationData: listPresentationData, title: .text("SpaceGram AI"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        return (controllerState, (ItemListNodeState(presentationData: listPresentationData, entries: entries, style: .blocks, animateChanges: false), arguments))
    }
    let controller = ItemListController(context: context, state: signal)
    controller.navigationPresentation = .default
    pushControllerImpl = { [weak controller] viewController in
        (controller?.navigationController as? NavigationController)?.pushViewController(viewController, animated: true)
    }
    return controller
}
