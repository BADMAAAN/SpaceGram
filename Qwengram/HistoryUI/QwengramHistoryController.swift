import AccountContext
import Display
import Foundation
import ItemListUI
import LocalizedPeerData
import QwengramStrings
import Postbox
import PresentationDataUtils
import QwengramHistoryStorage
import QwengramMediaArchive
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData

private struct QwengramHistoryEntry: ItemListNodeEntry {
    let stableId: Int32
    let section: ItemListSectionId
    let title: String
    let text: String
    var action: (() -> Void)? = nil

    static func == (lhs: QwengramHistoryEntry, rhs: QwengramHistoryEntry) -> Bool {
        return lhs.stableId == rhs.stableId && lhs.section == rhs.section && lhs.title == rhs.title && lhs.text == rhs.text && (lhs.action == nil) == (rhs.action == nil)
    }

    static func < (lhs: QwengramHistoryEntry, rhs: QwengramHistoryEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        if let action = action {
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: text, labelStyle: .multilineDetailText, sectionId: section, style: .blocks, action: action)
        } else {
            return ItemListTextItem(presentationData: presentationData, text: .plain(title.isEmpty ? text : "\(title)\n\n\(text)"), sectionId: section)
        }
    }
}

private struct QwengramHistoryRow {
    let record: QwengramHistoryRecord
    let peer: EnginePeer?
}

private func qwengramHistoryPeer(transaction: Transaction, packedId: Int64) -> EnginePeer? {
    // Archive JSON can decode an arbitrary Int64. Reject invalid packed IDs
    // before PeerId's debug assertions, and only resolve supported cloud peers.
    guard packedId >= 0, UInt64(packedId) >> 59 == 0 else {
        return nil
    }
    let namespace = Int32((packedId >> 32) & 7)
    guard namespace == Namespaces.Peer.CloudUser._internalGetInt32Value()
        || namespace == Namespaces.Peer.CloudGroup._internalGetInt32Value()
        || namespace == Namespaces.Peer.CloudChannel._internalGetInt32Value() else {
        return nil
    }
    switch transaction.getPeer(EnginePeer.Id(packedId)) {
    case let user as TelegramUser:
        return .user(user)
    case let group as TelegramGroup:
        return .legacyGroup(group)
    case let channel as TelegramChannel:
        return .channel(channel)
    default:
        return nil
    }
}

private func qwengramHistoryPeerTitle(_ peer: EnginePeer?, presentationData: PresentationData) -> String {
    let title = peer?.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder).trimmingCharacters(in: .whitespacesAndNewlines)
    return title.flatMap { $0.isEmpty ? nil : $0 } ?? "Unknown or deleted peer"
}

private func qwengramHistoryDateFormatter() -> DateFormatter {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .medium
    return formatter
}

public func qwengramHistoryController(context: AccountContext) -> ViewController {
    var pushControllerImpl: ((ViewController) -> Void)?
    let formatter = qwengramHistoryDateFormatter()
    // Read only the selected account's local archive. No network peer fetches.
    let archive: Signal<([QwengramHistoryRow], Int)?, NoError> = .single(nil)
    |> then(context.account.postbox.combinedView(keys: [.orderedItemList(id: QwengramHistoryCollection.id)])
    |> mapToSignal { _ in context.account.postbox.transaction { transaction -> ([QwengramHistoryRow], Int)? in
        let result = QwengramHistoryStore.listRecords(transaction: transaction)
        let rows = qwengramHistoryNewestFirst(result.records).map { record in
            QwengramHistoryRow(record: record, peer: qwengramHistoryPeer(transaction: transaction, packedId: record.key.peerId))
        }
        return (rows, result.unreadableCount)
    } })
    let signal = combineLatest(context.sharedContext.presentationData, archive)
    |> deliverOnMainQueue
    |> map { presentationData, archive -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var entries: [QwengramHistoryEntry] = []
        if let (rows, unreadableCount) = archive {
            if unreadableCount > 0 {
                entries.append(QwengramHistoryEntry(stableId: 0, section: 0, title: "Some history could not be read", text: "\(unreadableCount) saved records are damaged or unsupported. Other records remain available."))
            }
            if rows.isEmpty {
                entries.append(QwengramHistoryEntry(stableId: 1, section: 1, title: unreadableCount == 0 ? "No saved history" : "No readable history", text: unreadableCount == 0 ? "Saved edits and server deletions will appear here." : "The saved records could not be loaded."))
            }
            for (index, row) in rows.enumerated() {
                let event = qwengramHistoryLatestEvent(row.record)
                let status = event.map { qwengramHistoryEventTitle($0, detail: false, lang: presentationData.strings.baseLanguageCode) } ?? "Saved revision"
                let mediaLabel = row.record.events.contains(where: { !($0.mediaAssetIds ?? []).isEmpty }) ? " · " + ngI18n("Qwengram.Archive", presentationData.strings.baseLanguageCode) : ""
                let time = qwengramHistoryDate(event?.observedTimestamp ?? qwengramHistoryLatestTimestamp(row.record), formatter: formatter)
                entries.append(QwengramHistoryEntry(
                    stableId: Int32(index + 2),
                    section: 1,
                    title: qwengramHistoryPeerTitle(row.peer, presentationData: presentationData),
                    text: "\(status)\(mediaLabel) · \(time)\n\(qwengramHistoryPreview(row.record))",
                    action: { pushControllerImpl?(qwengramHistoryDetailController(context: context, key: row.record.key)) }
                ))
            }
        } else {
            entries.append(QwengramHistoryEntry(stableId: 0, section: 0, title: "", text: "Loading history…"))
        }
        let listPresentationData = ItemListPresentationData(presentationData)
        let controllerState = ItemListControllerState(presentationData: listPresentationData, title: .text("History"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        return (controllerState, (ItemListNodeState(presentationData: listPresentationData, entries: entries, style: .blocks, animateChanges: false), ()))
    }
    let controller = ItemListController(context: context, state: signal)
    controller.navigationPresentation = .default
    pushControllerImpl = { [weak controller] viewController in
        (controller?.navigationController as? NavigationController)?.pushViewController(viewController, animated: true)
    }
    return controller
}

private enum QwengramHistoryDetailState {
    case loading
    case loaded(QwengramHistoryRow)
    case missing
    case unreadable
}

public func qwengramMessageHistoryAvailable(context: AccountContext, messageId: EngineMessage.Id) -> Signal<Bool, NoError> {
    guard messageId.namespace == Namespaces.Message.Cloud,
          messageId.peerId.namespace == Namespaces.Peer.CloudUser
            || messageId.peerId.namespace == Namespaces.Peer.CloudGroup
            || messageId.peerId.namespace == Namespaces.Peer.CloudChannel else {
        return .single(false)
    }
    let key = QwengramHistoryMessageKey(peerId: messageId.peerId.toInt64(), namespace: messageId.namespace, id: messageId.id)
    return context.account.postbox.transaction { transaction -> Bool in
        do {
            return try QwengramHistoryStore.load(transaction: transaction, key: key) != nil
        } catch {
            // A missing/invalid archive must never prevent the normal menu opening.
            return false
        }
    }
}

public func qwengramHistoryDetailController(context: AccountContext, messageId: EngineMessage.Id) -> ViewController {
    let key = QwengramHistoryMessageKey(peerId: messageId.peerId.toInt64(), namespace: messageId.namespace, id: messageId.id)
    return qwengramHistoryDetailController(context: context, key: key)
}

private func qwengramHistoryDetailController(context: AccountContext, key: QwengramHistoryMessageKey) -> ViewController {
    weak var presentingController: ItemListController?
    let root = QwengramMediaArchive.root(mediaBoxPath: context.account.postbox.mediaBox.basePath)
    let formatter = qwengramHistoryDateFormatter()
    let record: Signal<QwengramHistoryDetailState, NoError> = .single(.loading)
    |> then(context.account.postbox.combinedView(keys: [.orderedItemList(id: QwengramHistoryCollection.id)])
    |> mapToSignal { _ in context.account.postbox.transaction { transaction -> QwengramHistoryDetailState in
        do {
            guard let record = try QwengramHistoryStore.load(transaction: transaction, key: key) else {
                return .missing
            }
            return .loaded(QwengramHistoryRow(record: record, peer: qwengramHistoryPeer(transaction: transaction, packedId: key.peerId)))
        } catch {
            return .unreadable
        }
    } })
    let mediaRecord = record |> mapToSignal { state -> Signal<(QwengramHistoryDetailState, [QwengramArchivedAsset]), NoError> in
        guard case let .loaded(row) = state else { return .single((state, [])) }
        let ids = row.record.events.flatMap { $0.mediaAssetIds ?? [] }
        return Signal { subscriber in
            QwengramMediaArchive.list(root: root, ids: ids) { assets in
                subscriber.putNext((state, assets))
                subscriber.putCompletion()
            }
            return EmptyDisposable
        }
    }
    let signal = combineLatest(context.sharedContext.presentationData, mediaRecord)
    |> deliverOnMainQueue
    |> map { presentationData, mediaState -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let (state, assets) = mediaState
        let lang = presentationData.strings.baseLanguageCode
        var entries: [QwengramHistoryEntry] = []
        switch state {
        case .loading:
            entries.append(QwengramHistoryEntry(stableId: 0, section: 0, title: "", text: "Loading history…"))
        case .missing:
            entries.append(QwengramHistoryEntry(stableId: 0, section: 0, title: "History no longer available", text: "This record may have reached the archive retention limit."))
        case .unreadable:
            entries.append(QwengramHistoryEntry(stableId: 0, section: 0, title: "Unable to read history", text: "This saved record is damaged or unsupported."))
        case let .loaded(row):
            entries.append(QwengramHistoryEntry(stableId: 0, section: 0, title: qwengramHistoryPeerTitle(row.peer, presentationData: presentationData), text: "Saved history · Oldest first"))
            let timeline = qwengramHistoryTimeline(row.record, lang: lang)
            if timeline.isEmpty {
                entries.append(QwengramHistoryEntry(stableId: 1, section: 1, title: "No saved revisions or events", text: "This record has no saved content."))
            }
            for (index, item) in timeline.enumerated() {
                entries.append(QwengramHistoryEntry(stableId: Int32(index + 1), section: Int32(index + 1), title: "\(item.title) · \(qwengramHistoryDate(item.timestamp, formatter: formatter))", text: item.text))
            }
            let linkedIds = Set(row.record.events.flatMap { $0.mediaAssetIds ?? [] })
            let missing = linkedIds.subtracting(assets.map { $0.id }).count
            if missing > 0 || row.record.events.contains(where: { $0.mediaCaptureId != nil && ($0.mediaAssetIds ?? []).isEmpty }) {
                entries.append(QwengramHistoryEntry(stableId: Int32(entries.count + 1), section: Int32(entries.count + 1), title: ngI18n("Qwengram.Archive", lang), text: ngI18n("Qwengram.MediaUnavailable", lang)))
            }
            for asset in assets {
                entries.append(QwengramHistoryEntry(stableId: Int32(entries.count + 1), section: Int32(entries.count + 1), title: asset.fileName, text: ngI18n("Qwengram.OpenMedia", lang) + " · " + ByteCountFormatter.string(fromByteCount: asset.bytes, countStyle: .file), action: {
                    QwengramMediaArchive.preview(root: root, id: asset.id) { result in
                        Queue.mainQueue().async {
                            guard let controller = presentingController, controller.isViewLoaded, controller.view.window != nil else { return }
                            switch result {
                            case let .success(lease):
                                controller.present(QwengramMediaPreviewController(lease: lease), animated: true)
                            case .failure:
                                let data = context.sharedContext.currentPresentationData.with { $0 }
                                controller.present(textAlertController(context: context, title: ngI18n("Qwengram.Archive", data.strings.baseLanguageCode), text: ngI18n("Qwengram.MediaUnavailable", data.strings.baseLanguageCode), actions: [TextAlertAction(type: .defaultAction, title: data.strings.Common_OK, action: {})]), in: .window(.root))
                            }
                        }
                    }
                }))
            }
        }
        let listPresentationData = ItemListPresentationData(presentationData)
        let controllerState = ItemListControllerState(presentationData: listPresentationData, title: .text("Message History"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        return (controllerState, (ItemListNodeState(presentationData: listPresentationData, entries: entries, style: .blocks, animateChanges: false), ()))
    }
    let controller = ItemListController(context: context, state: signal)
    controller.navigationPresentation = .default
    presentingController = controller
    return controller
}
