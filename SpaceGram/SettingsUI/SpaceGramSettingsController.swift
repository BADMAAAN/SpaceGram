import AccountContext
import Display
import Foundation
import ItemListUI
import NagramSettings
import NagramSettingsUI
import SettingsUI
import SpaceGramAppearance
import SpaceGramHistoryUI
import SpaceGramSettings
import SpaceGramSettingsSignal
import SpaceGramStrings
import SwiftSignalKit
import TelegramPresentationData
import UIKit

public func spaceGramSettingsIcon() -> UIImage? {
    guard let path = Bundle.main.path(forResource: "SpaceGramSettings", ofType: "png"), let image = UIImage(contentsOfFile: path) else { return nil }
    return UIGraphicsImageRenderer(size: CGSize(width: 29, height: 29)).image { _ in
        UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: 29, height: 29), cornerRadius: 7).addClip()
        image.draw(in: CGRect(x: 0, y: 0, width: 29, height: 29))
    }
}

private func spaceGramTile(_ symbol: String, section: Int32) -> UIImage? {
    let colors: [UIColor] = [.systemBlue, .systemIndigo, .systemGreen, .systemPurple, .systemOrange, .systemTeal, .systemPink]
    return UIGraphicsImageRenderer(size: CGSize(width: 29, height: 29)).image { _ in
        colors[Int(section) % colors.count].setFill()
        UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: 29, height: 29), cornerRadius: 7).fill()
        let configuration = UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)
        if let image = UIImage(systemName: symbol, withConfiguration: configuration)?.withTintColor(.white, renderingMode: .alwaysOriginal) {
            image.draw(in: CGRect(x: (29 - image.size.width) / 2, y: (29 - image.size.height) / 2, width: image.size.width, height: image.size.height))
        }
    }
}

private struct SpaceGramHubEntry: ItemListNodeEntry {
    let stableId: Int32
    let section: ItemListSectionId
    let title: String
    var symbol: String = ""
    var value: Bool? = nil
    var header: Bool = false
    var footer: Bool = false
    var action: (() -> Void)? = nil
    var updated: ((Bool) -> Void)? = nil

    static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.stableId == rhs.stableId && lhs.section == rhs.section && lhs.title == rhs.title && lhs.symbol == rhs.symbol && lhs.value == rhs.value && lhs.header == rhs.header && lhs.footer == rhs.footer
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.stableId < rhs.stableId }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        if header { return ItemListSectionHeaderItem(presentationData: presentationData, text: title, sectionId: section) }
        if footer { return ItemListTextItem(presentationData: presentationData, text: .plain(title), sectionId: section) }
        let icon = symbol == "spacegram" ? spaceGramSettingsIcon() : spaceGramTile(symbol, section: section)
        if let value, let updated {
            return ItemListSwitchItem(presentationData: presentationData, systemStyle: .glass, icon: icon, title: title, value: value, maximumNumberOfLines: 2, sectionId: section, style: .blocks, updated: updated)
        }
        return ItemListDisclosureItem(presentationData: presentationData, systemStyle: .glass, icon: icon, title: title, label: "", sectionId: section, style: .blocks, action: action)
    }
}

public func spaceGramSettingsController(context: AccountContext, openAccounts: ((ViewController) -> Void)? = nil) -> ViewController {
    var push: ((ViewController) -> Void)?
    var accounts: (() -> Void)?
    let signal = combineLatest(context.sharedContext.presentationData, spaceGramSettingsChangesSignal())
    |> deliverOnMainQueue
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let lang = presentationData.strings.baseLanguageCode
        let settings = SpaceGramSettings.shared
        let enhancements = NagramSettings.shared
        var entries: [SpaceGramHubEntry] = []
        // Fixed section/row identities. Optional rows never renumber other rows.
        func header(_ section: Int32, _ key: String) {
            entries.append(SpaceGramHubEntry(stableId: section * 100, section: section, title: ngI18n(key, lang), header: true))
        }
        func link(_ id: Int32, _ key: String, _ symbol: String, _ action: @escaping () -> Void) {
            entries.append(SpaceGramHubEntry(stableId: id, section: id / 100, title: ngI18n(key, lang), symbol: symbol, action: action))
        }
        func toggle(_ id: Int32, _ key: String, _ symbol: String, _ value: Bool, _ updated: @escaping (Bool) -> Void) {
            entries.append(SpaceGramHubEntry(stableId: id, section: id / 100, title: ngI18n(key, lang), symbol: symbol, value: value, updated: updated))
        }
        func footer(_ id: Int32, _ key: String) {
            entries.append(SpaceGramHubEntry(stableId: id, section: id / 100, title: ngI18n(key, lang), footer: true))
        }
        header(0, "SpaceGram.Hub.Information")
        link(1, "SpaceGram.Hub.About", "spacegram", { push?(spaceGramAboutController(context: context)) })
        if openAccounts != nil {
            header(1, "SpaceGram.Hub.Accounts")
            link(101, "SpaceGram.Hub.AllAccounts", "person.2.fill", { accounts?() })
        }
        header(2, "SpaceGram.Hub.Chat")
        link(201, "SpaceGram.Hub.Deleted", "trash.fill", { push?(spaceGramHistoryController(context: context, initialKind: .deleted)) })
        link(202, "SpaceGram.Hub.Edits", "pencil", { push?(spaceGramHistoryController(context: context, initialKind: .edited)) })
        toggle(203, "SpaceGram.Hub.GhostButton", "eye.slash", settings.showGhostButton, { settings.showGhostButton = $0 })
        toggle(204, "SpaceGram.Hub.JumpToFirst", "arrow.up.to.line", settings.showJumpToFirst, { settings.showJumpToFirst = $0 })
        toggle(205, "SpaceGram.Hub.ForwardWithoutName", "arrowshape.turn.up.right", enhancements.isMessageMenuItemEnabled(.forwardWithoutQuote), { enhancements.setMessageMenuItemEnabled(.forwardWithoutQuote, enabled: $0) })
        footer(290, "SpaceGram.Hub.HistoryInfo")
        header(3, "SpaceGram.Hub.Ghost")
        toggle(301, "SpaceGram.Hub.Ghost", "eye.slash.fill", settings.ghostMode.isFull, { settings.setGhostMode($0) })
        toggle(302, "SpaceGram.AutomaticReads", "checkmark.message", settings.suppressAutomaticReads, { settings.suppressAutomaticReads = $0 })
        toggle(303, "SpaceGram.Stories", "eye.slash", settings.hideStoryViews, { settings.hideStoryViews = $0 })
        toggle(304, "SpaceGram.Online", "network", settings.hideOnlinePresence, { settings.hideOnlinePresence = $0 })
        toggle(305, "SpaceGram.Activity", "ellipsis.bubble", settings.hideChatActivity, { settings.hideChatActivity = $0 })
        toggle(306, "SpaceGram.Hub.DelayedSend", "clock.arrow.circlepath", settings.delayedSend, { settings.delayedSend = $0 })
        footer(389, "SpaceGram.Hub.DelayedSendInfo")
        footer(390, "SpaceGram.GhostInfo")
        header(4, "SpaceGram.Privacy")
        toggle(404, "SpaceGram.Hub.DisableAutoDownload", "arrow.down.circle", settings.disableAutoDownload, { settings.disableAutoDownload = $0 })
        link(401, "SpaceGram.Privacy.Open", "lock.fill", { push?(spaceGramPrivacySettingsController(context: context)) })
        link(402, "SpaceGram.Hub.Downloads", "arrow.down.circle", { push?(dataAndStorageController(context: context)) })
        link(403, "SpaceGram.Hub.Proxy", "network", { push?(proxySettingsController(context: context)) })
        header(5, "SpaceGram.Hub.Interface")
        toggle(501, "SpaceGram.Hub.StoriesPanel", "rectangle.stack", !enhancements.hideStories, { enhancements.hideStories = !$0 })
        toggle(502, "SpaceGram.Hub.CompactChats", "list.bullet", enhancements.chatListCompact, { enhancements.chatListCompact = $0 })
        header(6, "SpaceGram.Hub.Messages")
        toggle(601, "SpaceGram.Hub.Formatter", "textformat", enhancements.showTextStyleToolbar, { enhancements.showTextStyleToolbar = $0 })
        toggle(602, "SpaceGram.Hub.TranslateBeforeSend", "character.bubble", enhancements.translateBeforeSend, { enhancements.translateBeforeSend = $0 })
        link(603, "SpaceGram.Hub.Translation", "globe", { push?(nagramSettingsController(context: context, deepLinkPath: "https://t.me/nasettings/chat?p=ios&r=TranslationProvider", unified: true)) })
        toggle(604, "SpaceGram.Hub.Seconds", "clock", enhancements.secondsInMessages, { enhancements.secondsInMessages = $0 })
        header(7, "SpaceGram.Hub.HistoryMedia")
        link(701, "SpaceGram.History", "clock.arrow.circlepath", { push?(spaceGramHistorySettingsController(context: context)) })
        link(702, "SpaceGram.Archive", "archivebox.fill", { push?(spaceGramMediaArchiveSettingsController(context: context)) })
        footer(790, "SpaceGram.ArchiveLimits")
        header(8, "SpaceGram.Tools")
        if settings.toolsEnabled {
            link(801, "SpaceGram.Hub.Qwen", "sparkles", { push?(spaceGramQwenAssistantController(context: context)) })
            link(802, "SpaceGram.Hub.Summarizer", "text.alignleft", { push?(spaceGramSummarizerController(context: context)) })
            link(803, "SpaceGram.Hub.Translator", "character.bubble", { push?(spaceGramTranslatorController(context: context)) })
            link(804, "SpaceGram.Hub.QR", "qrcode", { push?(spaceGramQRToolsController(context: context)) })
        }
        link(805, "SpaceGram.Provider", "slider.horizontal.3", { push?(spaceGramAISettingsController(context: context)) })
        header(9, "SpaceGram.Appearance")
        link(901, "SpaceGram.Hub.ThemeIcons", "paintpalette.fill", { push?(themeSettingsController(context: context)) })
        header(10, "SpaceGram.Advanced")
        link(1001, "SpaceGram.Hub.Enhancements", "slider.horizontal.3", { push?(nagramSettingsController(context: context, unified: true)) })
        toggle(1002, "SpaceGram.Enabled", "power", settings.spaceGramEnabled, { settings.spaceGramEnabled = $0 })
        toggle(1003, "SpaceGram.ToolsEnabled", "wrench.and.screwdriver", settings.botsHubEnabled, { settings.botsHubEnabled = $0 })
        if !settings.spaceGramEnabled { footer(1090, "SpaceGram.Disabled") }
        let data = spaceGramItemListPresentationData(presentationData)
        let state = ItemListControllerState(presentationData: data, title: .text("SpaceGram"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        // ItemList asserts strict ordering, including on its first transition.
        return (state, (ItemListNodeState(presentationData: data, entries: entries.sorted(), style: .blocks, animateChanges: false), NSNull()))
    }
    let controller = ItemListController(context: context, state: signal)
    controller.navigationPresentation = .default
    push = { [weak controller] in (controller?.navigationController as? NavigationController)?.pushViewController($0, animated: true) }
    accounts = { [weak controller] in if let controller { openAccounts?(controller) } }
    return controller
}

private func spaceGramAboutController(context: AccountContext) -> ViewController {
    let signal = context.sharedContext.presentationData |> map { presentationData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let lang = presentationData.strings.baseLanguageCode
        let keys = ["SpaceGram.Hub.AboutIntro", "SpaceGram.Hub.AboutGhost", "SpaceGram.Hub.AboutHistory", "SpaceGram.Hub.AboutMedia", "SpaceGram.Hub.AboutAI", "SpaceGram.Hub.AboutPrivacy"]
        let entries = keys.enumerated().map { index, key in
            SpaceGramHubEntry(stableId: Int32(index), section: Int32(index), title: ngI18n(key, lang), footer: true)
        }
        let data = spaceGramItemListPresentationData(presentationData)
        let state = ItemListControllerState(presentationData: data, title: .text(ngI18n("SpaceGram.Hub.About", lang)), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        return (state, (ItemListNodeState(presentationData: data, entries: entries, style: .blocks), NSNull()))
    }
    return ItemListController(context: context, state: signal)
}
