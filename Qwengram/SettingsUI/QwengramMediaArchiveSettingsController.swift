import AccountContext
import Display
import Foundation
import ItemListUI
import PresentationDataUtils
import QwengramHistoryStorage
import QwengramMediaArchive
import QwengramSettings
import QwengramSettingsSignal
import QwengramStrings
import SwiftSignalKit
import TelegramPresentationData

private struct QwengramMediaSettingsEntry: ItemListNodeEntry {
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

public func qwengramMediaArchiveSettingsController(context: AccountContext) -> ViewController {
    weak var controller: ItemListController?
    let root = QwengramMediaArchive.root(mediaBoxPath: context.account.postbox.mediaBox.basePath)
    var usage: QwengramMediaArchiveUsage?
    var policy = QwengramMediaArchivePolicy.default
    let revision = ValuePromise<Int32>(0, ignoreRepeated: false)
    var revisionValue: Int32 = 0
    let refresh: () -> Void = { revisionValue += 1; revision.set(revisionValue) }
    let alert: (String) -> Void = { message in
        let data = context.sharedContext.currentPresentationData.with { $0 }
        controller?.present(textAlertController(context: context, title: ngI18n("Qwengram.Archive", data.strings.baseLanguageCode), text: message, actions: [TextAlertAction(type: .defaultAction, title: data.strings.Common_OK, action: {})]), in: .window(.root))
    }
    let reload: () -> Void = {
        QwengramMediaArchive.usage(root: root) { result in
            Queue.mainQueue().async {
                switch result {
                case let .success(value): usage = value; policy = value.policy
                case .failure: alert("Unable to read Media Archive usage on this device.")
                }
                refresh()
            }
        }
    }
    let setPolicy: (QwengramMediaArchivePolicy) -> Void = { next in
        QwengramMediaArchive.setPolicy(root: root, policy: next) { success in
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
    let signal = combineLatest(context.sharedContext.presentationData, qwengramMediaArchiveSettingSignal(), revision.get())
    |> deliverOnMainQueue
    |> map { presentationData, enabled, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let lang = presentationData.strings.baseLanguageCode
        var entries: [QwengramMediaSettingsEntry] = [
            QwengramMediaSettingsEntry(stableId: 0, section: 0, title: ngI18n("Qwengram.MediaSettings.Enabled", lang), detail: "", value: enabled, updated: { QwengramSettings.shared.mediaArchiveEnabled = $0 })
        ]
        for (index, size) in QwengramMediaArchivePolicy.storagePresets.enumerated() {
            let label = ByteCountFormatter.string(fromByteCount: size, countStyle: .binary)
            entries.append(QwengramMediaSettingsEntry(stableId: Int32(index + 1), section: 1, title: (policy.storageLimitBytes == size ? "✓ " : "") + label, detail: "", action: {
                setPolicy(QwengramMediaArchivePolicy(storageLimitBytes: size, retentionDays: policy.retentionDays, automaticCleanup: policy.automaticCleanup))
            }))
        }
        for (index, days) in QwengramMediaArchivePolicy.retentionPresets.enumerated() {
            entries.append(QwengramMediaSettingsEntry(stableId: Int32(index + 5), section: 2, title: (policy.retentionDays == days ? "✓ " : "") + "\(days) " + ngI18n("Qwengram.MediaSettings.Days", lang), detail: "", action: {
                setPolicy(QwengramMediaArchivePolicy(storageLimitBytes: policy.storageLimitBytes, retentionDays: days, automaticCleanup: policy.automaticCleanup))
            }))
        }
        entries.append(QwengramMediaSettingsEntry(stableId: 8, section: 3, title: ngI18n("Qwengram.MediaSettings.Automatic", lang), detail: "", value: policy.automaticCleanup, updated: { value in
            setPolicy(QwengramMediaArchivePolicy(storageLimitBytes: policy.storageLimitBytes, retentionDays: policy.retentionDays, automaticCleanup: value))
        }))
        let used = usage.map { ByteCountFormatter.string(fromByteCount: $0.bytes, countStyle: .binary) } ?? "…"
        entries.append(QwengramMediaSettingsEntry(stableId: 9, section: 4, title: ngI18n("Qwengram.MediaSettings.Used", lang), detail: used))
        entries.append(QwengramMediaSettingsEntry(stableId: 10, section: 4, title: ngI18n("Qwengram.MediaSettings.Count", lang), detail: usage.map { String($0.assetCount) } ?? "…"))
        entries.append(QwengramMediaSettingsEntry(stableId: 11, section: 5, title: ngI18n("Qwengram.MediaSettings.CleanExpired", lang), detail: "", action: {
            let _ = context.account.postbox.transaction { transaction -> (Set<String>, Bool) in
                let references = QwengramHistoryStore.assetReferences(transaction: transaction)
                return (references.ids, references.complete)
            }.start(next: { references in
                QwengramMediaArchive.cleanExpired(root: root, referencedIds: references.0, referencesComplete: references.1) { success in
                    Queue.mainQueue().async { if success { reload() } else { alert("Unable to clean expired media.") } }
                }
            })
        }))
        entries.append(QwengramMediaSettingsEntry(stableId: 12, section: 5, title: ngI18n("Qwengram.History.ClearMedia", lang), detail: "", action: {
            confirm(ngI18n("Qwengram.History.ClearMedia", lang), "All saved media for this account will be removed. History text remains.", {
                QwengramMediaArchive.clear(root: root) { success in
                    Queue.mainQueue().async { if success { reload() } else { alert("Unable to clear Media Archive.") } }
                }
            })
        }))
        let listData = ItemListPresentationData(presentationData)
        let state = ItemListControllerState(presentationData: listData, title: .text(ngI18n("Qwengram.Archive", lang)), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        return (state, (ItemListNodeState(presentationData: listData, entries: entries, style: .blocks, animateChanges: true), ()))
    }
    let itemListController = ItemListController(context: context, state: signal)
    itemListController.navigationPresentation = .default
    controller = itemListController
    reload()
    return itemListController
}
