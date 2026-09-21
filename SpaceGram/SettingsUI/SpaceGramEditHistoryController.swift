import AccountContext
import Display
import Foundation
import ItemListUI
import SpaceGramHistoryStorage
import SpaceGramStrings
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import UIKit

private struct SpaceGramEditHistoryEntry: ItemListNodeEntry {
    let stableId: Int32
    let section: ItemListSectionId
    let text: String
    let kind: Int
    var copyText: String = ""

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.stableId < rhs.stableId }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        if kind == 0 {
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: section)
        } else if kind == 1 {
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: section)
        } else {
            return ItemListActionItem(presentationData: presentationData, title: text, kind: .generic, alignment: .natural, sectionId: section, style: .blocks, action: {
                UIPasteboard.general.string = self.copyText
            })
        }
    }
}

public func spaceGramEditHistoryController(context: AccountContext, record: SpaceGramHistoryRecord, current: EngineRawMessage) -> ViewController {
    let revisions = SpaceGramHistoryPresentationModel.editRevisions(record)
    let signal = context.sharedContext.presentationData
    |> deliverOnMainQueue
    |> map { presentationData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let language = presentationData.strings.baseLanguageCode
        var entries: [SpaceGramEditHistoryEntry] = []
        func append(section: Int32, title: String, timestamp: Int64, text: String) {
            let date = DateFormatter.localizedString(from: Date(timeIntervalSince1970: TimeInterval(timestamp)), dateStyle: .medium, timeStyle: .medium)
            entries.append(SpaceGramEditHistoryEntry(stableId: section * 3, section: section, text: title + " · " + date, kind: 0))
            entries.append(SpaceGramEditHistoryEntry(stableId: section * 3 + 1, section: section,
                text: text.isEmpty ? ngI18n("SpaceGram.History.NoText", language) : text, kind: 1))
            if !text.isEmpty {
                entries.append(SpaceGramEditHistoryEntry(stableId: section * 3 + 2, section: section,
                    text: ngI18n("SpaceGram.History.Copy", language), kind: 2, copyText: text))
            }
        }
        for (index, revision) in revisions.enumerated() {
            append(section: Int32(index), title: "\(index + 1). " + ngI18n("SpaceGram.History.Previous", language),
                timestamp: revision.snapshot.serverEditTimestamp ?? revision.snapshot.originalMessageTimestamp, text: revision.snapshot.text)
        }
        let edited = current.attributes.compactMap { $0 as? EditedMessageAttribute }.first
        append(section: Int32(revisions.count), title: ngI18n("SpaceGram.History.Current", language),
            timestamp: Int64(edited?.date ?? current.timestamp), text: current.text)
        let data = ItemListPresentationData(presentationData)
        let state = ItemListControllerState(presentationData: data, title: .text(ngI18n("SpaceGram.History.EditHistory", language)),
            leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        return (state, (ItemListNodeState(presentationData: data, entries: entries, style: .blocks), NSNull()))
    }
    return ItemListController(context: context, state: signal)
}
