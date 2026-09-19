import AccountContext
import Display
import Foundation
import ItemListUI
import LocalizedPeerData
import Postbox
import PresentationDataUtils
import SpaceGramAppearance
import SpaceGramHistoryStorage
import SpaceGramMediaArchive
import SpaceGramStrings
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData

private struct SpaceGramHistoryEntry: ItemListNodeEntry {
    let stableId: Int32
    let section: ItemListSectionId
    let title: String
    let text: String
    var action: (() -> Void)? = nil
    var textUpdated: ((String) -> Void)? = nil
    var snapshot: SpaceGramHistorySnapshot? = nil

    static func == (lhs: SpaceGramHistoryEntry, rhs: SpaceGramHistoryEntry) -> Bool {
        return lhs.stableId == rhs.stableId && lhs.section == rhs.section && lhs.title == rhs.title && lhs.text == rhs.text && lhs.snapshot == rhs.snapshot && (lhs.action == nil) == (rhs.action == nil)
    }

    static func < (lhs: SpaceGramHistoryEntry, rhs: SpaceGramHistoryEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        if let textUpdated = textUpdated {
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(string: title, textColor: presentationData.theme.list.itemPrimaryTextColor), text: text, placeholder: ngI18n("SpaceGram.History.SearchPlaceholder", presentationData.strings.baseLanguageCode), type: .regular(capitalization: false, autocorrection: false), clearType: .onFocus, sectionId: section, textUpdated: textUpdated, action: {})
        } else if let action = action {
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: text, labelStyle: .multilineDetailText, sectionId: section, style: .blocks, action: action)
        } else if let snapshot, !snapshot.text.isEmpty, snapshot.text.utf16.count <= 100_000, let context = arguments as? AccountContext {
            return ItemListTextItem(presentationData: presentationData, text: .custom(context: context, string: spaceGramHistoryRichText(snapshot: snapshot, title: title, details: text, presentationData: presentationData)), sectionId: section)
        } else {
            return ItemListTextItem(presentationData: presentationData, text: .plain(title.isEmpty ? text : "\(title)\n\n\(text)"), sectionId: section)
        }
    }
}

private struct SpaceGramHistoryRow {
    let record: SpaceGramHistoryRecord
    let peer: EnginePeer?
    let authors: [Int64: EnginePeer]
}

private struct SpaceGramHistoryArchiveSnapshot {
    let rows: [SpaceGramHistoryRow]
    let peers: [(Int64, String)]
    let unreadableCount: Int
    let totalCount: Int
    var availableAssetIds: Set<String>
}

private extension SpaceGramHistoryKind {
    func title(lang: String) -> String {
        switch self {
        case .all: return ngI18n("SpaceGram.History.All", lang)
        case .edited: return ngI18n("SpaceGram.History.Edited", lang)
        case .deleted: return ngI18n("SpaceGram.History.Deleted", lang)
        case .media: return ngI18n("SpaceGram.History.Media", lang)
        }
    }
}

private struct SpaceGramHistoryFilter: Equatable {
    var query = ""
    var kind: SpaceGramHistoryKind = .all
    var peerId: Int64?
    var showPeers = false
    var newestFirst = true
    var limit = 200
}

private func spaceGramHistoryMatches(_ row: SpaceGramHistoryRow, filter: SpaceGramHistoryFilter, presentationData: PresentationData) -> Bool {
    let titles = [spaceGramHistoryPeerTitle(row.peer, presentationData: presentationData)] + row.authors.values.map { spaceGramHistoryPeerTitle($0, presentationData: presentationData) }
    return SpaceGramHistoryQuery.matches(row.record, kind: filter.kind, peerId: filter.peerId, query: filter.query, peerTitles: titles)
}

private func spaceGramHistoryDisplayedEvent(_ record: SpaceGramHistoryRecord, kind: SpaceGramHistoryKind) -> SpaceGramHistoryEvent? {
    let events: [SpaceGramHistoryEvent]
    switch kind {
    case .all: return spaceGramHistoryLatestEvent(record)
    case .edited: events = record.events.filter { $0.type == .edit }
    case .deleted: events = record.events.filter { $0.type == .delete }
    case .media: events = record.events.filter { $0.mediaCaptureId != nil || !($0.mediaAssetIds ?? []).isEmpty }
    }
    return events.enumerated().max { lhs, rhs in
        lhs.element.observedTimestamp == rhs.element.observedTimestamp ? lhs.offset < rhs.offset : lhs.element.observedTimestamp < rhs.element.observedTimestamp
    }?.element ?? spaceGramHistoryLatestEvent(record)
}

private func spaceGramHistoryPeer(transaction: Transaction, packedId: Int64) -> EnginePeer? {
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

private func spaceGramHistoryPeerTitle(_ peer: EnginePeer?, presentationData: PresentationData) -> String {
    let title = peer?.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder).trimmingCharacters(in: .whitespacesAndNewlines)
    return title.flatMap { $0.isEmpty ? nil : $0 } ?? ngI18n("SpaceGram.History.UnknownPeer", presentationData.strings.baseLanguageCode)
}

private func spaceGramHistoryDateFormatter() -> DateFormatter {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.timeStyle = .medium
    return formatter
}

public func spaceGramHistoryController(context: AccountContext, initialKind: SpaceGramHistoryKind = .all, peerId: Int64? = nil) -> ViewController {
    var pushControllerImpl: ((ViewController) -> Void)?
    weak var presentingController: ItemListController?
    let formatter = spaceGramHistoryDateFormatter()
    var filterValue = SpaceGramHistoryFilter()
    filterValue.kind = initialKind
    filterValue.peerId = peerId
    let filterPromise = ValuePromise<SpaceGramHistoryFilter>(filterValue, ignoreRepeated: false)
    let updateFilter: (SpaceGramHistoryFilter) -> Void = { value in
        filterValue = value
        filterPromise.set(value)
    }
    let root = SpaceGramMediaArchive.root(mediaBoxPath: context.account.postbox.mediaBox.basePath)
    let confirm: (String, String, @escaping () -> Void) -> Void = { title, text, action in
        let data = context.sharedContext.currentPresentationData.with { $0 }
        presentingController?.present(textAlertController(context: context, title: title, text: text, actions: [
            TextAlertAction(type: .defaultAction, title: data.strings.Common_Cancel, action: {}),
            TextAlertAction(type: .destructiveAction, title: data.strings.Common_Delete, action: action)
        ]), in: .window(.root))
    }
    // Read only the selected account's local archive. No network peer fetches.
    let archive: Signal<SpaceGramHistoryArchiveSnapshot?, NoError> = .single(nil)
    |> then(combineLatest(context.account.postbox.combinedView(keys: [.orderedItemList(id: SpaceGramHistoryCollection.id)]), filterPromise.get(), context.sharedContext.presentationData)
    |> mapToSignal { _, filter, presentationData in context.account.postbox.transaction { transaction -> SpaceGramHistoryArchiveSnapshot in
        let result = SpaceGramHistoryStore.listRecords(transaction: transaction)
        let rows = spaceGramHistoryNewestFirst(result.records).map { record in
            var authors: [Int64: EnginePeer] = [:]
            for id in Set(record.revisions.compactMap { $0.snapshot.authorPeerId }) {
                authors[id] = spaceGramHistoryPeer(transaction: transaction, packedId: id)
            }
            return SpaceGramHistoryRow(record: record, peer: spaceGramHistoryPeer(transaction: transaction, packedId: record.key.peerId), authors: authors)
        }
        var peers: [Int64: String] = [:]
        for row in rows { peers[row.record.key.peerId] = spaceGramHistoryPeerTitle(row.peer, presentationData: presentationData) }
        let options = peers.map { ($0.key, $0.value) }.sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
        let matching = rows.filter { spaceGramHistoryMatches($0, filter: filter, presentationData: presentationData) }
        let ordered = filter.newestFirst ? matching : Array(matching.reversed())
        return SpaceGramHistoryArchiveSnapshot(rows: Array(ordered.prefix(filter.limit)), peers: options, unreadableCount: result.unreadableCount, totalCount: matching.count, availableAssetIds: [])
    } |> mapToSignal { snapshot -> Signal<SpaceGramHistoryArchiveSnapshot?, NoError> in
        let ids = snapshot.rows.flatMap { $0.record.events.flatMap { $0.mediaAssetIds ?? [] } }
        return Signal { subscriber in
            SpaceGramMediaArchive.available(root: root, ids: ids) { availableIds in
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
        var entries: [SpaceGramHistoryEntry] = []
        if let archive = archive {
            let rows = archive.rows
            let peers = archive.peers
            let unreadableCount = archive.unreadableCount
            let totalCount = archive.totalCount
            entries.append(SpaceGramHistoryEntry(stableId: 0, section: 0, title: ngI18n("SpaceGram.History.Search", lang), text: filterValue.query, textUpdated: { value in
                var next = filterValue
                next.query = value
                next.limit = 200
                updateFilter(next)
            }))
            for kind in SpaceGramHistoryKind.allCases {
                entries.append(SpaceGramHistoryEntry(stableId: Int32(1 + kind.rawValue), section: 1, title: (filterValue.kind == kind ? "✓ " : "") + kind.title(lang: lang), text: "", action: {
                    var next = filterValue
                    next.kind = kind
                    next.limit = 200
                    updateFilter(next)
                }))
            }
            entries.append(SpaceGramHistoryEntry(stableId: 5, section: 2, title: ngI18n("SpaceGram.History.Sort", lang), text: ngI18n(filterValue.newestFirst ? "SpaceGram.History.Newest" : "SpaceGram.History.Oldest", lang), action: {
                var next = filterValue
                next.newestFirst.toggle()
                next.limit = 200
                updateFilter(next)
            }))
            let selectedPeer = peers.first { $0.0 == filterValue.peerId }?.1 ?? ngI18n("SpaceGram.History.AllChats", lang)
            entries.append(SpaceGramHistoryEntry(stableId: 6, section: 2, title: ngI18n("SpaceGram.History.Chat", lang), text: selectedPeer, action: {
                var next = filterValue
                next.showPeers.toggle()
                updateFilter(next)
            }))
            if filterValue.showPeers {
                entries.append(SpaceGramHistoryEntry(stableId: 7, section: 2, title: ngI18n("SpaceGram.History.AllChats", lang), text: "", action: {
                    var next = filterValue
                    next.peerId = nil
                    next.showPeers = false
                    next.limit = 200
                    updateFilter(next)
                }))
                for (index, peer) in peers.enumerated() {
                    entries.append(SpaceGramHistoryEntry(stableId: Int32(index + 8), section: 2, title: peer.1, text: "", action: {
                        var next = filterValue
                        next.peerId = peer.0
                        next.showPeers = false
                        next.limit = 200
                        updateFilter(next)
                    }))
                }
            }
            if unreadableCount > 0 {
                entries.append(SpaceGramHistoryEntry(stableId: 2000, section: 3, title: ngI18n("SpaceGram.History.SomeUnreadable", lang), text: "\(unreadableCount) saved records are damaged or unsupported. Other records remain available."))
            }
            if rows.isEmpty {
                entries.append(SpaceGramHistoryEntry(stableId: 2001, section: 3, title: ngI18n("SpaceGram.History.NoMatches", lang), text: ngI18n("SpaceGram.History.TryFilters", lang)))
            }
            for (index, row) in rows.enumerated() {
                let event = spaceGramHistoryDisplayedEvent(row.record, kind: filterValue.kind)
                let status = event.map { spaceGramHistoryEventTitle($0, detail: false, lang: presentationData.strings.baseLanguageCode) } ?? ngI18n("SpaceGram.History.SavedRevision", lang)
                let mediaLabel = row.record.events.contains(where: { event in (event.mediaAssetIds ?? []).contains(where: { archive.availableAssetIds.contains($0) }) }) ? " · " + ngI18n("SpaceGram.Archive", presentationData.strings.baseLanguageCode) : ""
                let time = spaceGramHistoryDate(event?.observedTimestamp ?? spaceGramHistoryLatestTimestamp(row.record), formatter: formatter)
                let revision = row.record.revisions.first { $0.number == event?.revisionNumber } ?? row.record.revisions.last
                let author = revision?.snapshot.authorPeerId.flatMap { row.authors[$0] }.map { spaceGramHistoryPeerTitle($0, presentationData: presentationData) }
                entries.append(SpaceGramHistoryEntry(
                    stableId: Int32(index + 2002),
                    section: 3,
                    title: spaceGramHistoryPeerTitle(row.peer, presentationData: presentationData),
                    text: "\(status)\(mediaLabel) · \(time)\(author.map { " · " + $0 } ?? "")\n\(spaceGramHistoryPreview(row.record, event: event, lang: lang))",
                    action: { pushControllerImpl?(spaceGramHistoryDetailController(context: context, key: row.record.key)) }
                ))
            }
            if rows.count < totalCount {
                entries.append(SpaceGramHistoryEntry(stableId: 3500, section: 3, title: ngI18n("SpaceGram.History.ShowMore", lang), text: "\(rows.count) / \(totalCount)", action: {
                    var next = filterValue
                    next.limit += 200
                    updateFilter(next)
                }))
            }
            if let peerId = filterValue.peerId {
                entries.append(SpaceGramHistoryEntry(stableId: 4000, section: 4, title: ngI18n("SpaceGram.History.DeleteChat", lang), text: "", action: {
                    confirm(ngI18n("SpaceGram.History.DeleteChatConfirm", lang), "Saved history and linked media for this chat will be removed from this device.", {
                        let _ = context.account.postbox.transaction { transaction -> [String] in
                            SpaceGramHistoryStore.removePeer(transaction: transaction, peerId: peerId)
                        }.start(next: { ids in SpaceGramMediaArchive.remove(root: root, ids: ids) })
                    })
                }))
            }
            entries.append(SpaceGramHistoryEntry(stableId: 4001, section: 4, title: ngI18n("SpaceGram.History.ClearAll", lang), text: "", action: {
                confirm(ngI18n("SpaceGram.History.ClearConfirm", lang), ngI18n("SpaceGram.History.ClearInfo", lang), {
                    let _ = context.account.postbox.transaction { transaction -> [String] in
                        SpaceGramHistoryStore.clearArchiveWithAssets(transaction: transaction)
                    }.start(next: { ids in SpaceGramMediaArchive.remove(root: root, ids: ids) })
                })
            }))
            entries.append(SpaceGramHistoryEntry(stableId: 4002, section: 4, title: ngI18n("SpaceGram.History.ClearMedia", lang), text: "", action: {
                confirm("Clear Media Archive?", "All locally saved media for this account will be removed. History text and events will remain.", {
                    SpaceGramMediaArchive.clear(root: root) { success in
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
            entries.append(SpaceGramHistoryEntry(stableId: 0, section: 0, title: "", text: ngI18n("SpaceGram.History.Loading", lang)))
        }
        let listPresentationData = spaceGramItemListPresentationData(presentationData)
        let controllerState = ItemListControllerState(presentationData: listPresentationData, title: .text(ngI18n(initialKind == .deleted ? "SpaceGram.Hub.Deleted" : initialKind == .edited ? "SpaceGram.Hub.Edits" : "SpaceGram.History", lang)), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        return (controllerState, (ItemListNodeState(presentationData: listPresentationData, entries: entries, style: .blocks, animateChanges: false), context))
    }
    let controller = ItemListController(context: context, state: signal)
    controller.navigationPresentation = .default
    presentingController = controller
    pushControllerImpl = { [weak controller] viewController in
        (controller?.navigationController as? NavigationController)?.pushViewController(viewController, animated: true)
    }
    return controller
}

private enum SpaceGramHistoryDetailState {
    case loading
    case loaded(SpaceGramHistoryRow)
    case missing
    case unreadable
}

public struct SpaceGramMessageHistoryIndicators {
    public let hasHistory: Bool
    public let hasEdits: Bool
    public let hasDeletes: Bool

    public init(hasHistory: Bool = false, hasEdits: Bool = false, hasDeletes: Bool = false) {
        self.hasHistory = hasHistory
        self.hasEdits = hasEdits
        self.hasDeletes = hasDeletes
    }
}

public func spaceGramMessageHistoryIndicators(context: AccountContext, messageId: EngineMessage.Id) -> Signal<SpaceGramMessageHistoryIndicators, NoError> {
    guard messageId.namespace == Namespaces.Message.Cloud,
          messageId.peerId.namespace == Namespaces.Peer.CloudUser
            || messageId.peerId.namespace == Namespaces.Peer.CloudGroup
            || messageId.peerId.namespace == Namespaces.Peer.CloudChannel else {
        return .single(SpaceGramMessageHistoryIndicators())
    }
    let key = SpaceGramHistoryMessageKey(peerId: messageId.peerId.toInt64(), namespace: messageId.namespace, id: messageId.id)
    return context.account.postbox.transaction { transaction -> SpaceGramMessageHistoryIndicators in
        guard let record = try? SpaceGramHistoryStore.load(transaction: transaction, key: key) else {
            return SpaceGramMessageHistoryIndicators()
        }
        return SpaceGramMessageHistoryIndicators(hasHistory: true, hasEdits: record.events.contains(where: { $0.type == .edit }), hasDeletes: record.events.contains(where: { $0.type == .delete }))
    }
}

public func spaceGramMessageHistoryAvailable(context: AccountContext, messageId: EngineMessage.Id) -> Signal<Bool, NoError> {
    guard messageId.namespace == Namespaces.Message.Cloud,
          messageId.peerId.namespace == Namespaces.Peer.CloudUser
            || messageId.peerId.namespace == Namespaces.Peer.CloudGroup
            || messageId.peerId.namespace == Namespaces.Peer.CloudChannel else {
        return .single(false)
    }
    let key = SpaceGramHistoryMessageKey(peerId: messageId.peerId.toInt64(), namespace: messageId.namespace, id: messageId.id)
    return context.account.postbox.transaction { transaction -> Bool in
        do {
            return try SpaceGramHistoryStore.load(transaction: transaction, key: key) != nil
        } catch {
            // A missing/invalid archive must never prevent the normal menu opening.
            return false
        }
    }
}

public func spaceGramHistoryDetailController(context: AccountContext, messageId: EngineMessage.Id) -> ViewController {
    let key = SpaceGramHistoryMessageKey(peerId: messageId.peerId.toInt64(), namespace: messageId.namespace, id: messageId.id)
    return spaceGramHistoryDetailController(context: context, key: key)
}

private func spaceGramHistoryDetailController(context: AccountContext, key: SpaceGramHistoryMessageKey) -> ViewController {
    weak var presentingController: ItemListController?
    let root = SpaceGramMediaArchive.root(mediaBoxPath: context.account.postbox.mediaBox.basePath)
    let formatter = spaceGramHistoryDateFormatter()
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
    let record: Signal<SpaceGramHistoryDetailState, NoError> = .single(.loading)
    |> then(context.account.postbox.combinedView(keys: [.orderedItemList(id: SpaceGramHistoryCollection.id)])
    |> mapToSignal { _ in context.account.postbox.transaction { transaction -> SpaceGramHistoryDetailState in
        do {
            guard let record = try SpaceGramHistoryStore.load(transaction: transaction, key: key) else {
                return .missing
            }
            var authors: [Int64: EnginePeer] = [:]
            for id in Set(record.revisions.compactMap { $0.snapshot.authorPeerId }) {
                authors[id] = spaceGramHistoryPeer(transaction: transaction, packedId: id)
            }
            return .loaded(SpaceGramHistoryRow(record: record, peer: spaceGramHistoryPeer(transaction: transaction, packedId: key.peerId), authors: authors))
        } catch {
            return .unreadable
        }
    } })
    let mediaRecord = record |> mapToSignal { state -> Signal<(SpaceGramHistoryDetailState, [String: SpaceGramArchivedAssetState]), NoError> in
        guard case let .loaded(row) = state else { return .single((state, [:])) }
        let ids = row.record.events.flatMap { $0.mediaAssetIds ?? [] }
        var capturedAt: [String: Int64] = [:]
        for event in row.record.events {
            for id in event.mediaAssetIds ?? [] { capturedAt[id] = event.observedTimestamp }
        }
        return Signal { subscriber in
            SpaceGramMediaArchive.states(root: root, ids: ids, capturedAt: capturedAt) { states in
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
        var entries: [SpaceGramHistoryEntry] = []
        switch state {
        case .loading:
            entries.append(SpaceGramHistoryEntry(stableId: 0, section: 0, title: "", text: ngI18n("SpaceGram.History.Loading", lang)))
        case .missing:
            entries.append(SpaceGramHistoryEntry(stableId: 0, section: 0, title: ngI18n("SpaceGram.History.Missing", lang), text: ngI18n("SpaceGram.History.RetentionMissing", lang)))
        case .unreadable:
            entries.append(SpaceGramHistoryEntry(stableId: 0, section: 0, title: ngI18n("SpaceGram.History.Unreadable", lang), text: ngI18n("SpaceGram.History.Damaged", lang)))
        case let .loaded(row):
            entries.append(SpaceGramHistoryEntry(stableId: 0, section: 0, title: spaceGramHistoryPeerTitle(row.peer, presentationData: presentationData), text: ngI18n("SpaceGram.History.OldestFirst", lang)))
            let timeline = spaceGramHistoryTimeline(row.record, lang: lang)
            if timeline.isEmpty {
                entries.append(SpaceGramHistoryEntry(stableId: 1, section: 1, title: ngI18n("SpaceGram.History.NoEvents", lang), text: ngI18n("SpaceGram.History.EmptyRecord", lang)))
            }
            var nextId: Int32 = 1
            for (index, item) in timeline.enumerated() {
                let section = Int32(index + 1)
                var details = [item.text]
                if let snapshot = item.snapshot {
                    if let authorId = snapshot.authorPeerId {
                        let author = row.authors[authorId].map { spaceGramHistoryPeerTitle($0, presentationData: presentationData) } ?? "Peer \(authorId)"
                        details.append(ngI18n("SpaceGram.History.Author", lang) + ": " + author)
                    }
                    if !snapshot.entities.isEmpty {
                        details.append(ngI18n("SpaceGram.History.Formatting", lang) + ": " + snapshot.entities.map { entity in
                            let attributes = entity.attributes.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
                            return "\(entity.type) [\(entity.offset), \(entity.length)]" + (attributes.isEmpty ? "" : " (\(attributes))")
                        }.joined(separator: "; "))
                    }
                    if !snapshot.media.isEmpty {
                        details.append(ngI18n("SpaceGram.History.Media", lang) + ": " + snapshot.media.map { $0.filename ?? $0.type }.joined(separator: ", "))
                    }
                }
                entries.append(SpaceGramHistoryEntry(stableId: nextId, section: section, title: "\(item.title) · \(spaceGramHistoryDate(item.timestamp, formatter: formatter))", text: details.joined(separator: "\n"), snapshot: item.snapshot))
                nextId += 1
                if let eventIndex = item.eventIndex {
                    let event = row.record.events[eventIndex]
                    if (event.mediaAssetIds ?? []).isEmpty && (event.mediaCaptureId != nil || item.snapshot?.media.isEmpty == false) {
                        entries.append(SpaceGramHistoryEntry(stableId: nextId, section: section, title: ngI18n("SpaceGram.History.Media", lang), text: ngI18n(event.mediaCaptureId == nil ? "SpaceGram.History.NoBinary" : "SpaceGram.History.CaptureFailed", lang)))
                        nextId += 1
                    }
                    for id in event.mediaAssetIds ?? [] {
                        let assetState = assetStates[id] ?? .missing
                        switch assetState {
                        case let .available(asset):
                            entries.append(SpaceGramHistoryEntry(stableId: nextId, section: section, title: asset.fileName, text: ngI18n("SpaceGram.History.AssetAvailable", lang) + " · " + ByteCountFormatter.string(fromByteCount: asset.bytes, countStyle: .file), action: {
                                SpaceGramMediaArchive.preview(root: root, id: asset.id) { result in
                                    Queue.mainQueue().async {
                                        guard let controller = presentingController, controller.isViewLoaded, controller.view.window != nil else { return }
                                        switch result {
                                        case let .success(lease): controller.present(SpaceGramMediaPreviewController(lease: lease), animated: true)
                                        case .failure:
                                            let data = context.sharedContext.currentPresentationData.with { $0 }
                                            controller.present(textAlertController(context: context, title: ngI18n("SpaceGram.Archive", data.strings.baseLanguageCode), text: ngI18n("SpaceGram.MediaUnavailable", data.strings.baseLanguageCode), actions: [TextAlertAction(type: .defaultAction, title: data.strings.Common_OK, action: {})]), in: .window(.root))
                                        }
                                    }
                                }
                            }))
                        case .expired:
                            entries.append(SpaceGramHistoryEntry(stableId: nextId, section: section, title: ngI18n("SpaceGram.History.Media", lang), text: ngI18n("SpaceGram.History.AssetExpired", lang)))
                        case .missing:
                            entries.append(SpaceGramHistoryEntry(stableId: nextId, section: section, title: ngI18n("SpaceGram.History.Media", lang), text: ngI18n("SpaceGram.History.AssetMissing", lang)))
                        case .corrupt:
                            entries.append(SpaceGramHistoryEntry(stableId: nextId, section: section, title: ngI18n("SpaceGram.History.Media", lang), text: ngI18n("SpaceGram.History.AssetCorrupt", lang)))
                        }
                        nextId += 1
                    }
                    entries.append(SpaceGramHistoryEntry(stableId: nextId, section: section, title: ngI18n("SpaceGram.History.DeleteEvent", lang), text: "", action: {
                        confirm(ngI18n("SpaceGram.History.DeleteEventConfirm", lang), ngI18n("SpaceGram.History.DeleteEventInfo", lang), {
                            let _ = context.account.postbox.transaction { transaction -> [String] in
                                do { return try SpaceGramHistoryStore.removeEvent(transaction: transaction, key: key, index: eventIndex, expected: event) }
                                catch { showRemovalError(); return [] }
                            }.start(next: { ids in SpaceGramMediaArchive.remove(root: root, ids: ids) })
                        })
                    }))
                } else if let number = item.revisionNumber {
                    if item.snapshot?.media.isEmpty == false {
                        entries.append(SpaceGramHistoryEntry(stableId: nextId, section: section, title: ngI18n("SpaceGram.History.Media", lang), text: ngI18n("SpaceGram.History.NoBinary", lang)))
                        nextId += 1
                    }
                    entries.append(SpaceGramHistoryEntry(stableId: nextId, section: section, title: ngI18n("SpaceGram.History.DeleteRevision", lang), text: "", action: {
                        confirm(ngI18n("SpaceGram.History.DeleteRevisionConfirm", lang), ngI18n("SpaceGram.History.DeleteRevisionInfo", lang), {
                            let _ = context.account.postbox.transaction { transaction -> Void in
                                do { try SpaceGramHistoryStore.removeRevision(transaction: transaction, key: key, number: number) }
                                catch { showRemovalError() }
                            }.start()
                        })
                    }))
                }
                nextId += 1
            }
            entries.append(SpaceGramHistoryEntry(stableId: nextId, section: Int32(timeline.count + 1), title: ngI18n("SpaceGram.History.DeleteMessage", lang), text: "", action: {
                confirm(ngI18n("SpaceGram.History.DeleteMessageConfirm", lang), ngI18n("SpaceGram.History.DeleteMessageInfo", lang), {
                    let _ = context.account.postbox.transaction { transaction -> [String] in
                        do { return try SpaceGramHistoryStore.removeMessage(transaction: transaction, key: key) }
                        catch { showRemovalError(); return [] }
                    }.start(next: { ids in SpaceGramMediaArchive.remove(root: root, ids: ids) })
                })
            }))
        }
        let listPresentationData = spaceGramItemListPresentationData(presentationData)
        let controllerState = ItemListControllerState(presentationData: listPresentationData, title: .text(ngI18n("SpaceGram.History", lang)), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        return (controllerState, (ItemListNodeState(presentationData: listPresentationData, entries: entries, style: .blocks, animateChanges: false), context))
    }
    let controller = ItemListController(context: context, state: signal)
    controller.navigationPresentation = .default
    presentingController = controller
    return controller
}
