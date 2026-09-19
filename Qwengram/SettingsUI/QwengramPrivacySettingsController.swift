import AccountContext
import Display
import Foundation
import ItemListUI
import LocalAuth
import PresentationDataUtils
import QwengramAI
import QwengramHistoryStorage
import QwengramMediaArchive
import QwengramPrivacy
import QwengramStrings
import SettingsUI
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData

private enum QwengramPrivacyEntry: ItemListNodeEntry {
    case header(Int32, Int32, String)
    case toggle(Int32, Int32, String, Bool, (Bool) -> Void)
    case navigation(Int32, Int32, String, String, Bool, () -> Void)
    case action(Int32, Int32, String, Bool, () -> Void)
    case info(Int32, Int32, String)

    var section: ItemListSectionId {
        switch self {
        case let .header(_, section, _), let .toggle(_, section, _, _, _), let .navigation(_, section, _, _, _, _), let .action(_, section, _, _, _), let .info(_, section, _):
            return section
        }
    }

    var stableId: Int32 {
        switch self {
        case let .header(id, _, _), let .toggle(id, _, _, _, _), let .navigation(id, _, _, _, _, _), let .action(id, _, _, _, _), let .info(id, _, _):
            return id
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case let (.header(lId, lSection, lText), .header(rId, rSection, rText)), let (.info(lId, lSection, lText), .info(rId, rSection, rText)):
            return lId == rId && lSection == rSection && lText == rText
        case let (.toggle(lId, lSection, lTitle, lValue, _), .toggle(rId, rSection, rTitle, rValue, _)):
            return lId == rId && lSection == rSection && lTitle == rTitle && lValue == rValue
        case let (.navigation(lId, lSection, lTitle, lDetail, lEnabled, _), .navigation(rId, rSection, rTitle, rDetail, rEnabled, _)):
            return lId == rId && lSection == rSection && lTitle == rTitle && lDetail == rDetail && lEnabled == rEnabled
        case let (.action(lId, lSection, lTitle, lDestructive, _), .action(rId, rSection, rTitle, rDestructive, _)):
            return lId == rId && lSection == rSection && lTitle == rTitle && lDestructive == rDestructive
        default:
            return false
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.stableId < rhs.stableId }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        switch self {
        case let .header(_, section, title):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: title, sectionId: section)
        case let .toggle(_, section, title, value, updated):
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, title: title, value: value, sectionId: section, style: .blocks, updated: updated)
        case let .navigation(_, section, title, detail, enabled, action):
            return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, title: title, enabled: enabled, label: detail, sectionId: section, style: .blocks, action: action)
        case let .action(_, section, title, destructive, action):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: destructive ? .destructive : .generic, alignment: .natural, sectionId: section, style: .blocks, action: action)
        case let .info(_, section, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: section)
        }
    }
}

public func qwengramPrivacySettingsController(context: AccountContext) -> ViewController {
    weak var controller: ItemListController?
    var pushController: ((ViewController) -> Void)?
    let accountId = context.account.id.int64
    let mediaBoxPath = context.account.postbox.mediaBox.basePath
    let mediaRoot = QwengramMediaArchive.root(mediaBoxPath: mediaBoxPath)
    let conversations = QwengramConversationStore(mediaBoxPath: mediaBoxPath)
    let baseBundleId = Bundle.main.bundleIdentifier
    var policy = QwengramPrivacyPolicyStore.loadAccountPolicy(mediaBoxPath: mediaBoxPath)
    let revision = ValuePromise<Int32>(0, ignoreRepeated: false)
    var revisionValue: Int32 = 0
    let refresh: () -> Void = { revisionValue += 1; revision.set(revisionValue) }

    let showMessage: (String, String) -> Void = { title, text in
        let data = context.sharedContext.currentPresentationData.with { $0 }
        controller?.present(textAlertController(context: context, title: title, text: text, actions: [TextAlertAction(type: .defaultAction, title: data.strings.Common_OK, action: {})]), in: .window(.root))
    }
    let confirm: (String, String, @escaping () -> Void) -> Void = { title, text, action in
        let data = context.sharedContext.currentPresentationData.with { $0 }
        controller?.present(textAlertController(context: context, title: title, text: text, actions: [
            TextAlertAction(type: .defaultAction, title: data.strings.Common_Cancel, action: {}),
            TextAlertAction(type: .destructiveAction, title: data.strings.Common_Delete, action: action)
        ]), in: .window(.root))
    }
    let updatePolicy: ((inout QwengramPrivacyPolicy) -> Void) -> Void = { update in
        var next = policy
        update(&next)
        if QwengramPrivacyPolicyStore.saveAccountPolicy(next, accountId: accountId, mediaBoxPath: mediaBoxPath, baseBundleId: baseBundleId) {
            policy = next
            refresh()
        } else {
            let lang = context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode
            showMessage(ngI18n("Qwengram.Privacy", lang), ngI18n("Qwengram.Privacy.SaveFailed", lang))
        }
    }
    let clearHistory: () -> Void = {
        let _ = context.account.postbox.transaction { transaction -> [String] in
            QwengramHistoryStore.clearArchiveWithAssets(transaction: transaction)
        }.start(next: { ids in
            QwengramMediaArchive.remove(root: mediaRoot, ids: ids)
            Queue.mainQueue().async {
                let lang = context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode
                showMessage(ngI18n("Qwengram.Privacy.ClearHistory", lang), ngI18n("Qwengram.Privacy.HistoryCleared", lang))
            }
        })
    }
    let clearConversations: (@escaping (Bool) -> Void) -> Void = { completion in
        conversations.clear { result in
            Queue.mainQueue().async {
                if case .success = result { completion(true) } else { completion(false) }
            }
        }
    }
    let clearAccountPolicy: () -> Void = {
        QwengramPrivacyPolicyStore.clearAccountPolicy(accountId: accountId, mediaBoxPath: mediaBoxPath, baseBundleId: baseBundleId)
        policy = .default
        refresh()
    }
    let clearAll: () -> Void = {
        let _ = context.account.postbox.transaction { transaction -> Void in
            QwengramHistoryStore.clearArchive(transaction: transaction)
        }.start(next: {
            QwengramMediaArchive.clear(root: mediaRoot) { mediaSuccess in
                clearConversations { conversationsSuccess in
                    var keySuccess = true
                    do { try QwengramAIKeychain.deleteQwenAPIKey(accountId: accountId) } catch { keySuccess = false }
                    clearAccountPolicy()
                    let lang = context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode
                    showMessage(ngI18n("Qwengram.Privacy.ClearAll", lang), ngI18n(mediaSuccess && conversationsSuccess && keySuccess ? "Qwengram.Privacy.AllCleared" : "Qwengram.Privacy.AllClearPartial", lang))
                }
            }
        })
    }

    let signal = combineLatest(context.sharedContext.presentationData, context.sharedContext.accountManager.accessChallengeData(), revision.get())
    |> deliverOnMainQueue
    |> map { presentationData, accessChallenge, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let lang = presentationData.strings.baseLanguageCode
        let lockEnabled = accessChallenge.data.isLockable
        let biometric: String
        switch LocalAuth.biometricAuthentication {
        case .faceId?: biometric = "Face ID"
        case .touchId?: biometric = "Touch ID"
        case nil: biometric = ngI18n("Qwengram.Privacy.BiometricsUnavailable", lang)
        }
        let clearMediaAction: () -> Void = {
            confirm(ngI18n("Qwengram.Privacy.ClearMedia", lang), ngI18n("Qwengram.Privacy.ClearMediaConfirm", lang), {
                QwengramMediaArchive.clear(root: mediaRoot) { success in
                    Queue.mainQueue().async {
                        showMessage(ngI18n("Qwengram.Privacy.ClearMedia", lang), ngI18n(success ? "Qwengram.Privacy.MediaCleared" : "Qwengram.Privacy.MediaClearFailed", lang))
                    }
                }
            })
        }
        let clearConversationsAction: () -> Void = {
            confirm(ngI18n("Qwengram.Privacy.ClearConversations", lang), ngI18n("Qwengram.Privacy.ClearConversationsConfirm", lang), {
                clearConversations { success in
                    showMessage(ngI18n("Qwengram.Privacy.ClearConversations", lang), ngI18n(success ? "Qwengram.Privacy.ConversationsCleared" : "Qwengram.Privacy.ConversationsClearFailed", lang))
                }
            })
        }
        let clearAPIKeyAction: () -> Void = {
            confirm(ngI18n("Qwengram.Privacy.ClearAPIKey", lang), ngI18n("Qwengram.Privacy.ClearAPIKeyConfirm", lang), {
                do {
                    try QwengramAIKeychain.deleteQwenAPIKey(accountId: accountId)
                    showMessage(ngI18n("Qwengram.Privacy.ClearAPIKey", lang), ngI18n("Qwengram.Privacy.APIKeyCleared", lang))
                } catch {
                    showMessage(ngI18n("Qwengram.Privacy.ClearAPIKey", lang), ngI18n("Qwengram.Privacy.APIKeyClearFailed", lang))
                }
            })
        }
        let clearSettingsAction: () -> Void = {
            confirm(ngI18n("Qwengram.Privacy.ClearLocalSettings", lang), ngI18n("Qwengram.Privacy.ClearSettingsConfirm", lang), {
                clearAccountPolicy()
                showMessage(ngI18n("Qwengram.Privacy.ClearLocalSettings", lang), ngI18n("Qwengram.Privacy.SettingsCleared", lang))
            })
        }
        let clearAllAction: () -> Void = {
            confirm(ngI18n("Qwengram.Privacy.ClearAll", lang), ngI18n("Qwengram.Privacy.ClearAllConfirm", lang), {
                confirm(ngI18n("Qwengram.Privacy.ConfirmRemoval", lang), ngI18n("Qwengram.Privacy.ClearAllConfirmAgain", lang), clearAll)
            })
        }
        var entries: [QwengramPrivacyEntry] = [
            .header(0, 0, ngI18n("Qwengram.Privacy.AppLock", lang)),
            .navigation(1, 0, ngI18n("Qwengram.Privacy.ConfigureAppLock", lang), lockEnabled ? ngI18n("Qwengram.On", lang) : ngI18n("Qwengram.Off", lang), true, { pushController?(passcodeOptionsController(context: context)) }),
            .info(2, 0, biometric + ". " + ngI18n("Qwengram.Privacy.AppLockInfo", lang))
        ]
        if lockEnabled {
            entries.append(.action(3, 0, ngI18n("Qwengram.Privacy.LockNow", lang), false, { context.sharedContext.appLockContext.lock() }))
        }
        entries.append(contentsOf: [
            .header(10, 1, ngI18n("Qwengram.Privacy.Notifications", lang)),
            .navigation(11, 1, ngI18n("Qwengram.Privacy.TelegramNotifications", lang), "", true, { pushController?(notificationsAndSoundsController(context: context, exceptionsList: nil)) }),
            .toggle(12, 1, ngI18n("Qwengram.Privacy.HideSender", lang), policy.hideNotificationSender, { value in updatePolicy { $0.hideNotificationSender = value } }),
            .toggle(13, 1, ngI18n("Qwengram.Privacy.HidePreview", lang), policy.hideNotificationPreview, { value in updatePolicy { $0.hideNotificationPreview = value } }),
            .toggle(14, 1, ngI18n("Qwengram.Privacy.GenericText", lang), policy.useGenericNotificationText, { value in updatePolicy { $0.useGenericNotificationText = value } }),
            .toggle(15, 1, ngI18n("Qwengram.Privacy.HideChatTitle", lang), policy.hideNotificationChatTitle, { value in updatePolicy { $0.hideNotificationChatTitle = value } }),
            .toggle(16, 1, ngI18n("Qwengram.Privacy.WhenAppLocked", lang), policy.notificationPrivacyWhenAppLocked, { value in updatePolicy { $0.notificationPrivacyWhenAppLocked = value } }),
            .info(17, 1, ngI18n("Qwengram.Privacy.NotificationInfo", lang)),
            .header(20, 2, ngI18n("Qwengram.Privacy.Metadata", lang)),
            .toggle(21, 2, ngI18n("Qwengram.Privacy.StripMetadata", lang), policy.stripPhotoMetadata, { value in updatePolicy { $0.stripPhotoMetadata = value } }),
            .info(22, 2, ngI18n("Qwengram.Privacy.MetadataInfo", lang)),
            .header(30, 3, ngI18n("Qwengram.Privacy.LocalData", lang)),
            .action(31, 3, ngI18n("Qwengram.Privacy.ClearHistory", lang), true, { confirm(ngI18n("Qwengram.Privacy.ClearHistory", lang), ngI18n("Qwengram.Privacy.ClearHistoryConfirm", lang), clearHistory) }),
            .action(32, 3, ngI18n("Qwengram.Privacy.ClearMedia", lang), true, clearMediaAction),
            .action(33, 3, ngI18n("Qwengram.Privacy.ClearConversations", lang), true, clearConversationsAction),
            .action(34, 3, ngI18n("Qwengram.Privacy.ClearAPIKey", lang), true, clearAPIKeyAction),
            .action(35, 3, ngI18n("Qwengram.Privacy.ClearLocalSettings", lang), true, clearSettingsAction),
            .action(36, 3, ngI18n("Qwengram.Privacy.ClearAll", lang), true, clearAllAction),
            .header(40, 4, ngI18n("Qwengram.Privacy.Emergency", lang)),
            .info(41, 4, ngI18n("Qwengram.Privacy.EmergencyInfo", lang))
        ])
        let listData = ItemListPresentationData(presentationData)
        let state = ItemListControllerState(presentationData: listData, title: .text(ngI18n("Qwengram.Privacy", lang)), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        return (state, (ItemListNodeState(presentationData: listData, entries: entries, style: .blocks, animateChanges: true), ()))
    }
    let itemListController = ItemListController(context: context, state: signal)
    itemListController.navigationPresentation = .default
    controller = itemListController
    pushController = { [weak itemListController] value in
        (itemListController?.navigationController as? NavigationController)?.pushViewController(value, animated: true)
    }
    return itemListController
}
