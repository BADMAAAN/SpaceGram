import AccountContext
import Display
import ItemListUI
import NagramLinkMetadata
import NagramSettings
import NagramSettingsSignal
import SpaceGramStrings
import PresentationDataUtils
import SwiftSignalKit
import TelegramPresentationData

private final class NagramInlineBotRulesArguments {
}

private enum NagramInlineBotRulesEntry: ItemListNodeEntry {
    case rule(Int, String, Bool)
    case footer(Int, String)

    var section: ItemListSectionId { return 0 }
    var stableId: Int { switch self { case let .rule(index, _, _): return index; case let .footer(index, _): return index } }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.stableId < rhs.stableId }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        switch self {
        case let .rule(_, username, approved):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: "@\(username)", value: approved, sectionId: self.section, style: .blocks, updated: { value in
                var selected = Set(NagramSettings.shared.approvedInlineBots.split(separator: " ").map(String.init))
                if value { selected.insert(username.lowercased()) } else { selected.remove(username.lowercased()) }
                NagramSettings.shared.approvedInlineBots = selected.sorted().joined(separator: " ")
            })
        case let .footer(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

public func nagramInlineBotRulesController(context: AccountContext) -> ViewController {
    NagramLinkMetadata.shared.refreshIfNeeded(engine: context.engine)
    let signal = combineLatest(context.sharedContext.presentationData, nagramStringSignal("spacegram.settings.approvedInlineBots", defaultValue: ""))
    |> deliverOnMainQueue
    |> map { presentationData, approvedBots -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let lang = presentationData.strings.baseLanguageCode
        var entries: [NagramInlineBotRulesEntry] = []
        for (index, rule) in NagramLinkMetadata.shared.currentInlineBotRules().enumerated() {
            entries.append(.rule(index * 2, rule.username, approvedBots.split(separator: " ").contains(Substring(rule.username.lowercased()))))
            entries.append(.footer(index * 2 + 1, rule.rules.joined(separator: "\n")))
        }
        entries.append(.footer(entries.count, ngI18n("Nagram.InlineBotRules.Footer", lang)))
        return (
            ItemListControllerState(presentationData: ItemListPresentationData(presentationData), title: .text(ngI18n("Nagram.InlineBotRules", lang)), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)),
            (ItemListNodeState(presentationData: ItemListPresentationData(presentationData), entries: entries, style: .blocks), NagramInlineBotRulesArguments())
        )
    }
    return ItemListController(context: context, state: signal)
}
