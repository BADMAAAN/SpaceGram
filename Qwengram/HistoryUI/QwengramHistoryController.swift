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
    var textUpdated: ((String) -> Void)? = nil

    static func == (lhs: QwengramHistoryEntry, rhs: QwengramHistoryEntry) -> Bool {
        return lhs.stableId == rhs.stableId && lhs.section == rhs.section && lhs.title == rhs.title && lhs.text == rhs.text && (lhs.action == nil) == (rhs.action == nil)
    }

    static func < (lhs: QwengramHistoryEntry, rhs: QwengramHistoryEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        if let textUpdated = textUpdated {
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(string: title, textColor: presentationData.theme.list.itemPrimaryTextColor), text: text, placeholder: ngI18n("Qwengram.History.SearchPlaceholder", presentationData.strings.baseLanguageCode), type: .regular(capitalization: false, autocorrection: false), clearType: .onFocus, sectionId: section, textUpdated: textUpdated, action: {})
        } else if let action = action {
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: text, labelStyle: .multilineDetailText, sectionId: section, style: .blocks, action: action)
        } else {
            return ItemListTextItem(presentationData: presentationData, text: .plain(title.isEmpty ? text : "\(title)\n\n\(text)"), sectionId: section)
        }
    }
}

private struct QwengramHistoryRow {
    let record: QwengramHistoryRecord
    let peer: EnginePeer?
    let authors: [Int64: EnginePeer]
}

private struct QwengramHistoryArchiveSnapshot {
    let rows: [QwengramHistoryRow]
    let peers: [(Int64, String)]
    let unreadableCount: Int
    let totalCount: Int
    var availableAssetIds: Set<String>
}

private enum QwengramHistoryKind: Int, CaseIterable {
    case all, edited, deleted, media
    func title(lang: String) -> String {
        switch self {
        case .all: return ngI18n("Qwengram.History.All", lang)
        case .edited: return ngI18n("Qwengram.History.Edited", lang)
        case .deleted: return ngI18n("Qwengram.History.Deleted", lang)
        case .media: return ngI18n("Qwengram.History.Media", lang)
        }
    }
}

private struct QwengramHistoryFilter {
    var query = ""
    var kind: QwengramHistoryKind = .all
    var peerId: Int64?
    var showPeers = false
    var newestFirst = true
    var limit = 200
}

private func qwengramHistoryMatches(_ row: QwengramHistoryRow, filter: QwengramHistoryFilter, presentationData: PresentationData) -> Bool {
    let record = row.record
    if let peerId = filter.peerId, record.key.peerId != peerId { return false }
    switch filter.kind {
    case .all: break
    case .edited: if !record.events.contains(where: { $0.type == .edit }) { return false }
    case .deleted: if !record.events.contains(where: { $0.type == .delete }) { return false }
    case .media: if !record.revisions.contains(where: { !$0.snapshot.media.isEmpty }) && !record.events.contains(where: { $0.mediaCaptureId != nil || !($0.mediaAssetIds ?? []).isEmpty }) { return false }
    }
    let query = filter.query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !query.isEmpty else { return true }
    if qwengramHistoryPeerTitle(row.peer, presentationData: presentationData).localizedCaseInsensitiveContains(query) { return true }
    if row.authors.values.contains(where: { qwengramHistoryPeerTitle($0, presentationData: presentationData).localizedCaseInsensitiveContains(query) }) { return true }
    if record.revisions.contains(where: { $0.snapshot.text.localizedCaseInsensitiveContains(query) || $0.snapshot.media.contains(where: { $0.filename?.localizedCaseInsensitiveContains(query) == true }) }) { return true }
    return record.events.contains { $0.type.rawValue.localizedCaseInsensitiveContains(query) || $0.reason.rawValue.localizedCaseInsensitiveContains(query) }
}

private func qwengramHistoryDisplayedEvent(_ record: QwengramHistoryRecord, kind: QwengramHistoryKind) -> QwengramHistoryEvent? {
    let events: [QwengramHistoryEvent]
    switch kind {
    case .all: return qwengramHistoryLatestEvent(record)
    case .edited: events = record.events.filter { $0.type == .edit }
    case .deleted: events = record.events.filter { $0.type == .delete }
    case .media: events = record.events.filter { $0.mediaCaptureId != nil || !($0.mediaAssetIds ?? []).isEmpty }
    }
    return events.enumerated().max { lhs, rhs in
        lhs.element.observedTimestamp == rhs.element.observedTimestamp ? lhs.offset < rhs.offset : lhs.element.observedTimestamp < rhs.element.observedTimestamp
    }?.element ?? qwengramHistoryLatestEvent(record)
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
    weak var presentingController: ItemListController?
    let formatter = qwengramHistoryDateFormatter()
    var filterValue = QwengramHistoryFilter()
    let filterPromise = ValuePromise<QwengramHistoryFilter>(filterValue, ignoreRepeated: false)
    let updateFilter: (QwengramHistoryFilter) -> Void = { value in
        filterValue = value
        filterPromise.set(value)
    }
    let root = QwengramMediaArchive.root(mediaBoxPath: context.account.postbox.mediaBox.basePath)
    let confirm: (String, String, @escaping () -> Void) -> Void = { title, text, action in
        let data = context.sharedContext.currentPresentationData.with { $0 }
        presentingController?.present(textAlertController(context: context, title: title, text: text, actions: [
            TextAlertAction(type: .defaultAction, title: data.strings.Common_Cancel, action: {}),
            TextAlertAction(type: .destructiveAction, title: data.strings.Common_Delete, action: action)
        ]), in: .window(.root))
    }
    // Read only the selected account's local archive. No network peer fetches.
    let archive: Signal<QwengramHistoryArchiveSnapshot?, NoError> = .single(nil)
    |> then(combineLatest(context.account.postbox.combinedView(keys: [.orderedItemList(id: QwengramHistoryCollection.id)]), filterPromise.get(), context.sharedContext.presentationData)
    |> mapToSignal { _, filter, presentationData in context.account.postbox.transaction { transaction -> QwengramHistoryArchiveSnapshot in
        let result = QwengramHistoryStore.listRecords(transaction: transaction)
        let rows = qwengramHistoryNewestFirst(result.records).map { record in
            var authors: [Int64: EnginePeer] = [:]
            for id in Set(record.revisions.compactMap { $0.snapshot.authorPeerId }) {
                authors[id] = qwengramHistoryPeer(transaction: transaction, packedId: id)
            }
            return QwengramHistoryRow(record: record, peer: qwengramHistoryPeer(transaction: transaction, packedId: record.key.peerId), authors: authors)
        }
        var peers: [Int64: String] = [:]
        for row in rows { peers[row.record.key.peerId] = qwengramHistoryPeerTitle(row.peer, presentationData: presentationData) }
        let options = peers.map { ($0.key, $0.value) }.sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
        let matching = rows.filter { qwengramHistoryMatches($0, filter: filter, presentationData: presentationData) }
        let ordered = filter.newestFirst ? matching : Array(matching.reversed())
        return QwengramHistoryArchiveSnapshot(rows: Array(ordered.prefix(filter.limit)), peers: options, unreadableCount: result.unreadableCount, totalCount: matching.count, availableAssetIds: [])
    } |> mapToSignal { snapshot -> Signal<QwengramHistoryArchiveSnapshot?, NoError> in
        let ids = snapshot.rows.flatMap { $0.record.events.flatMap { $0.mediaAssetIds ?? [] } }
        return Signal { subscriber in
            QwengramMediaArchive.available(root: root, ids: ids) { availableIds in
                var result = snapshot
                result.availableAssetIds = availableIds
                subscriber.putNext(result)
                subscriber.putCompletion()
            }
            return EmptyDisposable
        }
    } })
    let signal = combineLatest(context.sharedContext.presentationData, archive)
    |> deliverOnMainQueue
    |> map { presentationData, archive -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let lang = presentationData.strings.baseLanguageCode
        var entries: [QwengramHistoryEntry] = []
        if let archive = archive {
            let rows = archive.rows
            let peers = archive.peers
            let unreadableCount = archive.unreadableCount
            let totalCount = archive.totalCount
            entries.append(QwengramHistoryEntry(stableId: 0, section: 0, title: ngI18n("Qwengram.History.Search", lang), text: filterValue.query, textUpdated: { value in
                var next = filterValue
                next.query = value
                next.limit = 200
                updateFilter(next)
            }))
            for kind in QwengramHistoryKind.allCases {
                entries.append(QwengramHistoryEntry(stableId: Int32(1 + kind.rawValue), section: 1, title: (filterValue.kind == kind ? "✓ " : "") + kind.title(lang: lang), text: "", action: {
                    var next = filterValue
                    next.kind = kind
                    next.limit = 200
                    updateFilter(next)
                }))
            }
            entries.append(QwengramHistoryEntry(stableId: 5, section: 2, title: ngI18n("Qwengram.History.Sort", lang), text: ngI18n(filterValue.newestFirst ? "Qwengram.History.Newest" : "Qwengram.History.Oldest", lang), action: {
                var next = filterValue
                next.newestFirst.toggle()
                next.limit = 200
                updateFilter(next)
            }))
            let selectedPeer = peers.first { $0.0 == filterValue.peerId }?.1 ?? ngI18n("Qwengram.History.AllChats", lang)
            entries.append(QwengramHistoryEntry(stableId: 6, section: 2, title: ngI18n("Qwengram.History.Chat", lang), text: selectedPeer, action: {
                var next = filterValue
                next.showPeers.toggle()
                updateFilter(next)
            }))
            if filterValue.showPeers {
                entries.append(QwengramHistoryEntry(stableId: 7, section: 2, title: ngI18n("Qwengram.History.AllChats", lang), text: "", action: {
                    var next = filterValue
                    next.peerId = nil
                    next.showPeers = false
                    next.limit = 200
                    updateFilter(next)
                }))
                for (index, peer) in peers.enumerated() {
                    entries.append(QwengramHistoryEntry(stableId: Int32(index + 8), section: 2, title: peer.1, text: "", action: {
                        var next = filterValue
                        next.peerId = peer.0
                        next.showPeers = false
                        next.limit = 200
                        updateFilter(next)
                    }))
                }
            }
            if unreadableCount > 0 {
                entries.append(QwengramHistoryEntry(stableId: 2000, section: 3, title: "Some history could not be read", text: "\(unreadableCount) saved records are damaged or unsupported. Other records remain available."))
            }
            if rows.isEmpty {
                entries.append(QwengramHistoryEntry(stableId: 2001, section: 3, title: ngI18n("Qwengram.History.NoMatches", lang), text: ngI18n("Qwengram.History.TryFilters", lang)))
            }
            for (index, row) in rows.enumerated() {
                let event = qwengramHistoryDisplayedEvent(row.record, kind: filterValue.kind)
                let status = event.map { qwengramHistoryEventTitle($0, detail: false, lang: presentationData.strings.baseLanguageCode) } ?? "Saved revision"
                let mediaLabel = row.record.events.contains(where: { event in (event.mediaAssetIds ?? []).contains(where: { archive.availableAssetIds.contains($0) }) }) ? " · " + ngI18n("Qwengram.Archive", presentationData.strings.baseLanguageCode) : ""
                let time = qwengramHistoryDate(event?.observedTimestamp ?? qwengramHistoryLatestTimestamp(row.record), formatter: formatter)
                let revision = row.record.revisions.first { $0.number == event?.revisionNumber } ?? row.record.revisions.last
                let author = revision?.snapshot.authorPeerId.flatMap { row.authors[$0] }.map { qwengramHistoryPeerTitle($0, presentationData: presentationData) }
                entries.append(QwengramHistoryEntry(
                    stableId: Int32(index + 2002),
                    section: 3,
                    title: qwengramHistoryPeerTitle(row.peer, presentationData: presentationData),
                    text: "\(status)\(mediaLabel) · \(time)\(author.map { " · " + $0 } ?? "")\n\(qwengramHistoryPreview(row.record, event: event))",
                    action: { pushControllerImpl?(qwengramHistoryDetailController(context: context, key: row.record.key)) }
                ))
            }
            if rows.count < totalCount {
                entries.append(QwengramHistoryEntry(stableId: 3500, section: 3, title: ngI18n("Qwengram.History.ShowMore", lang), text: "\(rows.count) / \(totalCount)", action: {
                    var next = filterValue
                    next.limit += 200
                    updateFilter(next)
                }))
            }
            if let peerId = filterValue.peerId {
                entries.append(QwengramHistoryEntry(stableId: 4000, section: 4, title: ngI18n("Qwengram.History.DeleteChat", lang), text: "", action: {
                    confirm("Delete chat history?", "Saved history and linked media for this chat will be removed from this device.", {
                        let _ = context.account.postbox.transaction { transaction -> [String] in
                            QwengramHistoryStore.removePeer(transaction: transaction, peerId: peerId)
                        }.start(next: { ids in QwengramMediaArchive.remove(root: root, ids: ids) })
                    })
                }))
            }
            entries.append(QwengramHistoryEntry(stableId: 4001, section: 4, title: ngI18n("Qwengram.History.ClearAll", lang), text: "", action: {
                confirm("Clear Message History?", "All saved history and linked media for this account will be removed from this device.", {
                    let _ = context.account.postbox.transaction { transaction -> [String] in
                        QwengramHistoryStore.clearArchiveWithAssets(transaction: transaction)
                    }.start(next: { ids in QwengramMediaArchive.remove(root: root, ids: ids) })
                })
            }))
            entries.append(QwengramHistoryEntry(stableId: 4002, section: 4, title: ngI18n("Qwengram.History.ClearMedia", lang), text: "", action: {
                confirm("Clear Media Archive?", "All locally saved media for this account will be removed. History text and events will remain.", {
                    QwengramMediaArchive.clear(root: root) { success in
                        if !success {
                            Queue.mainQueue().async {
                                let data = context.sharedContext.currentPresentationData.with { $0 }
                                presentingController?.present(textAlertController(context: context, title: "Media Archive", text: "Unable to clear saved media. Try again.", actions: [TextAlertAction(type: .defaultAction, title: data.strings.Common_OK, action: {})]), in: .window(.root))
                            }
                        }
                    }
                })
            }))
        } else {
            entries.append(QwengramHistoryEntry(stableId: 0, section: 0, title: "", text: "Loading history…"))
        }
        let listPresentationData = ItemListPresentationData(presentationData)
        let controllerState = ItemListControllerState(presentationData: listPresentationData, title: .text("History"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        return (controllerState, (ItemListNodeState(presentationData: listPresentationData, entries: entries, style: .blocks, animateChanges: false), ()))
    }
    let controller = ItemListController(context: context, state: signal)
    controller.navigationPresentation = .default
    presentingController = controller
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

public struct QwengramMessageHistoryIndicators {
    public let hasHistory: Bool
    public let hasEdits: Bool
    public let hasDeletes: Bool

    public init(hasHistory: Bool = false, hasEdits: Bool = false, hasDeletes: Bool = false) {
        self.hasHistory = hasHistory
        self.hasEdits = hasEdits
        self.hasDeletes = hasDeletes
    }
}

public func qwengramMessageHistoryIndicators(context: AccountContext, messageId: EngineMessage.Id) -> Signal<QwengramMessageHistoryIndicators, NoError> {
    guard messageId.namespace == Namespaces.Message.Cloud,
          messageId.peerId.namespace == Namespaces.Peer.CloudUser
            || messageId.peerId.namespace == Namespaces.Peer.CloudGroup
            || messageId.peerId.namespace == Namespaces.Peer.CloudChannel else {
        return .single(QwengramMessageHistoryIndicators())
    }
    let key = QwengramHistoryMessageKey(peerId: messageId.peerId.toInt64(), namespace: messageId.namespace, id: messageId.id)
    return context.account.postbox.transaction { transaction -> QwengramMessageHistoryIndicators in
        guard let record = try? QwengramHistoryStore.load(transaction: transaction, key: key) else {
            return QwengramMessageHistoryIndicators()
        }
        return QwengramMessageHistoryIndicators(hasHistory: true, hasEdits: record.events.contains(where: { $0.type == .edit }), hasDeletes: record.events.contains(where: { $0.type == .delete }))
    }
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
    let confirm: (String, String, @escaping () -> Void) -> Void = { title, text, action in
        let data = context.sharedContext.currentPresentationData.with { $0 }
        presentingController?.present(textAlertController(context: context, title: title, text: text, actions: [
            TextAlertAction(type: .defaultAction, title: data.strings.Common_Cancel, action: {}),
            TextAlertAction(type: .destructiveAction, title: data.strings.Common_Delete, action: action)
        ]), in: .window(.root))
    }
    let showRemovalError: () -> Void = {
        Queue.mainQueue().async {
            let data = context.sharedContext.currentPresentationData.with { $0 }
            presentingController?.present(textAlertController(context: context, title: "Message History", text: "Unable to remove saved history. Try again.", actions: [TextAlertAction(type: .defaultAction, title: data.strings.Common_OK, action: {})]), in: .window(.root))
        }
    }
    let record: Signal<QwengramHistoryDetailState, NoError> = .single(.loading)
    |> then(context.account.postbox.combinedView(keys: [.orderedItemList(id: QwengramHistoryCollection.id)])
    |> mapToSignal { _ in context.account.postbox.transaction { transaction -> QwengramHistoryDetailState in
        do {
            guard let record = try QwengramHistoryStore.load(transaction: transaction, key: key) else {
                return .missing
            }
            var authors: [Int64: EnginePeer] = [:]
            for id in Set(record.revisions.compactMap { $0.snapshot.authorPeerId }) {
                authors[id] = qwengramHistoryPeer(transaction: transaction, packedId: id)
            }
            return .loaded(QwengramHistoryRow(record: record, peer: qwengramHistoryPeer(transaction: transaction, packedId: key.peerId), authors: authors))
        } catch {
            return .unreadable
        }
    } })
    let mediaRecord = record |> mapToSignal { state -> Signal<(QwengramHistoryDetailState, [String: QwengramArchivedAssetState]), NoError> in
        guard case let .loaded(row) = state else { return .single((state, [:])) }
        let ids = row.record.events.flatMap { $0.mediaAssetIds ?? [] }
        var capturedAt: [String: Int64] = [:]
        for event in row.record.events {
            for id in event.mediaAssetIds ?? [] { capturedAt[id] = event.observedTimestamp }
        }
        return Signal { subscriber in
            QwengramMediaArchive.states(root: root, ids: ids, capturedAt: capturedAt) { states in
                subscriber.putNext((state, states))
                subscriber.putCompletion()
            }
            return EmptyDisposable
        }
    }
    let signal = combineLatest(context.sharedContext.presentationData, mediaRecord)
    |> deliverOnMainQueue
    |> map { presentationData, mediaState -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let (state, assetStates) = mediaState
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
            var nextId: Int32 = 1
            for (index, item) in timeline.enumerated() {
                let section = Int32(index + 1)
                var details = [item.text]
                if let snapshot = item.snapshot {
                    if let authorId = snapshot.authorPeerId {
                        let author = row.authors[authorId].map { qwengramHistoryPeerTitle($0, presentationData: presentationData) } ?? "Peer \(authorId)"
                        details.append("Author: \(author)")
                    }
                    if !snapshot.entities.isEmpty {
                        details.append("Formatting: " + snapshot.entities.map { entity in
                            let attributes = entity.attributes.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
                            return "\(entity.type) [\(entity.offset), \(entity.length)]" + (attributes.isEmpty ? "" : " (\(attributes))")
                        }.joined(separator: "; "))
                    }
                    if !snapshot.media.isEmpty {
                        details.append("Media: " + snapshot.media.map { $0.filename ?? $0.type }.joined(separator: ", "))
                    }
                }
                entries.append(QwengramHistoryEntry(stableId: nextId, section: section, title: "\(item.title) · \(qwengramHistoryDate(item.timestamp, formatter: formatter))", text: details.joined(separator: "\n")))
                nextId += 1
                if let eventIndex = item.eventIndex {
                    let event = row.record.events[eventIndex]
                    if (event.mediaAssetIds ?? []).isEmpty && (event.mediaCaptureId != nil || item.snapshot?.media.isEmpty == false) {
                        entries.append(QwengramHistoryEntry(stableId: nextId, section: section, title: ngI18n("Qwengram.History.Media", lang), text: ngI18n(event.mediaCaptureId == nil ? "Qwengram.History.NoBinary" : "Qwengram.History.CaptureFailed", lang)))
                        nextId += 1
                    }
                    for id in event.mediaAssetIds ?? [] {
                        let assetState = assetStates[id] ?? .missing
                        switch assetState {
                        case let .available(asset):
                            entries.append(QwengramHistoryEntry(stableId: nextId, section: section, title: asset.fileName, text: ngI18n("Qwengram.History.AssetAvailable", lang) + " · " + ByteCountFormatter.string(fromByteCount: asset.bytes, countStyle: .file), action: {
                                QwengramMediaArchive.preview(root: root, id: asset.id) { result in
                                    Queue.mainQueue().async {
                                        guard let controller = presentingController, controller.isViewLoaded, controller.view.window != nil else { return }
                                        switch result {
                                        case let .success(lease): controller.present(QwengramMediaPreviewController(lease: lease), animated: true)
                                        case .failure:
                                            let data = context.sharedContext.currentPresentationData.with { $0 }
                                            controller.present(textAlertController(context: context, title: ngI18n("Qwengram.Archive", data.strings.baseLanguageCode), text: ngI18n("Qwengram.MediaUnavailable", data.strings.baseLanguageCode), actions: [TextAlertAction(type: .defaultAction, title: data.strings.Common_OK, action: {})]), in: .window(.root))
                                        }
                                    }
                                }
                            }))
                        case .expired:
                            entries.append(QwengramHistoryEntry(stableId: nextId, section: section, title: ngI18n("Qwengram.History.Media", lang), text: ngI18n("Qwengram.History.AssetExpired", lang)))
                        case .missing:
                            entries.append(QwengramHistoryEntry(stableId: nextId, section: section, title: ngI18n("Qwengram.History.Media", lang), text: ngI18n("Qwengram.History.AssetMissing", lang)))
                        case .corrupt:
                            entries.append(QwengramHistoryEntry(stableId: nextId, section: section, title: ngI18n("Qwengram.History.Media", lang), text: ngI18n("Qwengram.History.AssetCorrupt", lang)))
                        }
                        nextId += 1
                    }
                    entries.append(QwengramHistoryEntry(stableId: nextId, section: section, title: ngI18n("Qwengram.History.DeleteEvent", lang), text: "", action: {
                        confirm("Delete saved event?", "This event, its saved revision and linked media will be removed from this device.", {
                            let _ = context.account.postbox.transaction { transaction -> [String] in
                                do { return try QwengramHistoryStore.removeEvent(transaction: transaction, key: key, index: eventIndex, expected: event) }
                                catch { showRemovalError(); return [] }
                            }.start(next: { ids in QwengramMediaArchive.remove(root: root, ids: ids) })
                        })
                    }))
                } else if let number = item.revisionNumber {
                    if item.snapshot?.media.isEmpty == false {
                        entries.append(QwengramHistoryEntry(stableId: nextId, section: section, title: ngI18n("Qwengram.History.Media", lang), text: ngI18n("Qwengram.History.NoBinary", lang)))
                        nextId += 1
                    }
                    entries.append(QwengramHistoryEntry(stableId: nextId, section: section, title: ngI18n("Qwengram.History.DeleteRevision", lang), text: "", action: {
                        confirm("Delete saved revision?", "This saved revision will be removed from this device.", {
                            let _ = context.account.postbox.transaction { transaction -> Void in
                                do { try QwengramHistoryStore.removeRevision(transaction: transaction, key: key, number: number) }
                                catch { showRemovalError() }
                            }.start()
                        })
                    }))
                }
                nextId += 1
            }
            entries.append(QwengramHistoryEntry(stableId: nextId, section: Int32(timeline.count + 1), title: ngI18n("Qwengram.History.DeleteMessage", lang), text: "", action: {
                confirm("Delete message history?", "All saved revisions, events and linked media for this message will be removed from this device.", {
                    let _ = context.account.postbox.transaction { transaction -> [String] in
                        do { return try QwengramHistoryStore.removeMessage(transaction: transaction, key: key) }
                        catch { showRemovalError(); return [] }
                    }.start(next: { ids in QwengramMediaArchive.remove(root: root, ids: ids) })
                })
            }))
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
