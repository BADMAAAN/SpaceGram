import AccountContext
import Display
import Foundation
import ItemListUI
import PresentationDataUtils
import SpaceGramAppearance
import SpaceGramHistoryStorage
import SpaceGramMediaArchive
import SpaceGramSettings
import SpaceGramSettingsSignal
import SpaceGramStrings
import SwiftSignalKit
import TelegramPresentationData

private struct SpaceGramMediaSettingsEntry: ItemListNodeEntry {
    let stableId: Int32
    let section: ItemListSectionId
    let title: String
    let detail: String
    var value: Bool? = nil
    var updated: ((Bool) -> Void)? = nil
    var action: (() -> Void)? = nil

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.stableId == rhs.stableId && lhs.section == rhs.section && lhs.title == rhs.title && lhs.detail == rhs.detail && lhs.value == rhs.value
    }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.stableId < rhs.stableId }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        if let value = value, let updated = updated {
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: section, style: .blocks, updated: updated)
        }
        if let action = action {
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, label: detail, sectionId: section, style: .blocks, action: action)
        }
        return ItemListTextItem(presentationData: presentationData, text: .plain(title + (detail.isEmpty ? "" : "\n" + detail)), sectionId: section)
    }
}

public func spaceGramMediaArchiveSettingsController(context: AccountContext) -> ViewController {
    weak var controller: ItemListController?
    let root = SpaceGramMediaArchive.root(mediaBoxPath: context.account.postbox.mediaBox.basePath)
    var usage: SpaceGramMediaArchiveUsage?
    var policy = SpaceGramMediaArchivePolicy.default
    let revision = ValuePromise<Int32>(0, ignoreRepeated: false)
    var revisionValue: Int32 = 0
    let refresh: () -> Void = { revisionValue += 1; revision.set(revisionValue) }
    let alert: (String) -> Void = { message in
        let data = context.sharedContext.currentPresentationData.with { $0 }
        controller?.present(textAlertController(context: context, title: ngI18n("SpaceGram.Archive", data.strings.baseLanguageCode), text: message, actions: [TextAlertAction(type: .defaultAction, title: data.strings.Common_OK, action: {})]), in: .window(.root))
    }
    let reload: () -> Void = {
        SpaceGramMediaArchive.usage(root: root) { result in
            Queue.mainQueue().async {
                switch result {
                case let .success(value): usage = value; policy = value.policy
                case let .failure(error):
                    if case .migrationConflict = error {
                        alert(ngI18n("SpaceGram.StorageMigrationConflict", context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode))
                    } else {
                        alert("Unable to read Media Archive usage on this device.")
                    }
                }
                refresh()
            }
        }
    }
    let setPolicy: (SpaceGramMediaArchivePolicy) -> Void = { next in
        SpaceGramMediaArchive.setPolicy(root: root, policy: next) { success in
            Queue.mainQueue().async {
                if success { policy = next; reload() }
                else { alert("Unable to update Media Archive settings.") }
            }
        }
    }
    let confirm: (String, String, @escaping () -> Void) -> Void = { title, body, action in
        let data = context.sharedContext.currentPresentationData.with { $0 }
        controller?.present(textAlertController(context: context, title: title, text: body, actions: [
            TextAlertAction(type: .defaultAction, title: data.strings.Common_Cancel, action: {}),
            TextAlertAction(type: .destructiveAction, title: data.strings.Common_Delete, action: action)
        ]), in: .window(.root))
    }
    let signal = combineLatest(context.sharedContext.presentationData, spaceGramMediaArchiveSettingSignal(), revision.get())
    |> deliverOnMainQueue
    |> map { presentationData, enabled, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let lang = presentationData.strings.baseLanguageCode
        var entries: [SpaceGramMediaSettingsEntry] = [
            SpaceGramMediaSettingsEntry(stableId: 0, section: 0, title: ngI18n("SpaceGram.MediaSettings.Enabled", lang), detail: "", value: enabled, updated: { SpaceGramSettings.shared.mediaArchiveEnabled = $0 })
        ]
        for (index, size) in SpaceGramMediaArchivePolicy.storagePresets.enumerated() {
            let label = ByteCountFormatter.string(fromByteCount: size, countStyle: .binary)
            entries.append(SpaceGramMediaSettingsEntry(stableId: Int32(index + 1), section: 1, title: (policy.storageLimitBytes == size ? "✓ " : "") + label, detail: "", action: {
                setPolicy(SpaceGramMediaArchivePolicy(storageLimitBytes: size, retentionDays: policy.retentionDays, automaticCleanup: policy.automaticCleanup))
            }))
        }
        for (index, days) in SpaceGramMediaArchivePolicy.retentionPresets.enumerated() {
            entries.append(SpaceGramMediaSettingsEntry(stableId: Int32(index + 5), section: 2, title: (policy.retentionDays == days ? "✓ " : "") + "\(days) " + ngI18n("SpaceGram.MediaSettings.Days", lang), detail: "", action: {
                setPolicy(SpaceGramMediaArchivePolicy(storageLimitBytes: policy.storageLimitBytes, retentionDays: days, automaticCleanup: policy.automaticCleanup))
            }))
        }
        entries.append(SpaceGramMediaSettingsEntry(stableId: 8, section: 3, title: ngI18n("SpaceGram.MediaSettings.Automatic", lang), detail: "", value: policy.automaticCleanup, updated: { value in
            setPolicy(SpaceGramMediaArchivePolicy(storageLimitBytes: policy.storageLimitBytes, retentionDays: policy.retentionDays, automaticCleanup: value))
        }))
        let used = usage.map { ByteCountFormatter.string(fromByteCount: $0.bytes, countStyle: .binary) } ?? "…"
        entries.append(SpaceGramMediaSettingsEntry(stableId: 9, section: 4, title: ngI18n("SpaceGram.MediaSettings.Used", lang), detail: used))
        entries.append(SpaceGramMediaSettingsEntry(stableId: 10, section: 4, title: ngI18n("SpaceGram.MediaSettings.Count", lang), detail: usage.map { String($0.assetCount) } ?? "…"))
        entries.append(SpaceGramMediaSettingsEntry(stableId: 11, section: 5, title: ngI18n("SpaceGram.MediaSettings.CleanExpired", lang), detail: "", action: {
            let _ = context.account.postbox.transaction { transaction -> (Set<String>, Bool) in
                let references = SpaceGramHistoryStore.assetReferences(transaction: transaction)
                return (references.ids, references.complete)
            }.start(next: { references in
                SpaceGramMediaArchive.cleanExpired(root: root, referencedIds: references.0, referencesComplete: references.1) { success in
                    Queue.mainQueue().async { if success { reload() } else { alert("Unable to clean expired media.") } }
                }
            })
        }))
        entries.append(SpaceGramMediaSettingsEntry(stableId: 12, section: 5, title: ngI18n("SpaceGram.History.ClearMedia", lang), detail: "", action: {
            confirm(ngI18n("SpaceGram.History.ClearMedia", lang), "All saved media for this account will be removed. History text remains.", {
                SpaceGramMediaArchive.clear(root: root) { success in
                    Queue.mainQueue().async { if success { reload() } else { alert("Unable to clear Media Archive.") } }
                }
            })
        }))
        let listData = spaceGramItemListPresentationData(presentationData)
        let state = ItemListControllerState(presentationData: listData, title: .text(ngI18n("SpaceGram.Archive", lang)), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        return (state, (ItemListNodeState(presentationData: listData, entries: entries, style: .blocks, animateChanges: true), ()))
    }
    let itemListController = ItemListController(context: context, state: signal)
    itemListController.navigationPresentation = .default
    controller = itemListController
    reload()
    return itemListController
}
