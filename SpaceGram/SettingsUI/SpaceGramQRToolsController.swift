import AccountContext
import AsyncDisplayKit
import Display
import Foundation
import ItemListUI
import PresentationDataUtils
import SpaceGramAppearance
import SpaceGramQR
import SpaceGramSettings
import SpaceGramSettingsSignal
import SpaceGramStrings
import SwiftSignalKit
import TelegramPresentationData
import UIKit

private enum SpaceGramQRToolsEntry: ItemListNodeEntry {
    case header(Int32, Int32, String)
    case input(Int32, Int32, String)
    case generate(Int32, Int32, Bool)
    case result(Int32, Int32, UIImage, Int32)
    case share(Int32, Int32, String, Bool)

    var section: ItemListSectionId {
        switch self { case let .header(_, section, _), let .input(_, section, _), let .generate(_, section, _), let .result(_, section, _, _), let .share(_, section, _, _): return section }
    }

    var stableId: Int32 {
        switch self { case let .header(id, _, _), let .input(id, _, _), let .generate(id, _, _), let .result(id, _, _, _), let .share(id, _, _, _): return id }
    }

    static func == (lhs: SpaceGramQRToolsEntry, rhs: SpaceGramQRToolsEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.header(lId, lSection, lText), .header(rId, rSection, rText)):
            return lId == rId && lSection == rSection && lText == rText
        case let (.input(lId, lSection, lText), .input(rId, rSection, rText)):
            return lId == rId && lSection == rSection && lText == rText
        case let (.generate(lId, lSection, lEnabled), .generate(rId, rSection, rEnabled)):
            return lId == rId && lSection == rSection && lEnabled == rEnabled
        case let (.result(lId, lSection, _, lGeneration), .result(rId, rSection, _, rGeneration)):
            return lId == rId && lSection == rSection && lGeneration == rGeneration
        case let (.share(lId, lSection, lTitle, lEnabled), .share(rId, rSection, rTitle, rEnabled)):
            return lId == rId && lSection == rSection && lTitle == rTitle && lEnabled == rEnabled
        default:
            return false
        }
    }

    static func < (lhs: SpaceGramQRToolsEntry, rhs: SpaceGramQRToolsEntry) -> Bool { lhs.stableId < rhs.stableId }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! SpaceGramQRToolsArguments
        switch self {
        case let .header(_, section, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: section)
        case let .input(_, section, text):
            let item = ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(string: ""), text: text, placeholder: arguments.placeholder, type: .regular(capitalization: false, autocorrection: false), clearType: .onFocus, sectionId: section, textUpdated: arguments.updateText, action: {})
            item.accessibilityLabel = arguments.textTitle
            return item
        case let .generate(_, section, enabled):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: arguments.generateTitle, kind: enabled ? .generic : .disabled, alignment: .natural, sectionId: section, style: .blocks, action: arguments.generate)
        case let .result(_, section, image, _):
            return SpaceGramQRImageItem(theme: presentationData.theme, image: image, sectionId: section)
        case let .share(_, section, title, enabled):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: title, kind: enabled ? .generic : .disabled, alignment: .natural, sectionId: section, style: .blocks, action: enabled ? arguments.share : {})
        }
    }
}

private final class SpaceGramQRToolsArguments {
    let updateText: (String) -> Void
    let generate: () -> Void
    let share: () -> Void
    var textTitle = ""
    var placeholder = ""
    var generateTitle = ""

    init(updateText: @escaping (String) -> Void, generate: @escaping () -> Void, share: @escaping () -> Void) {
        self.updateText = updateText
        self.generate = generate
        self.share = share
    }
}

public func spaceGramQRToolsController(context: AccountContext) -> ViewController {
    let updatePromise = ValuePromise<Int32>(0, ignoreRepeated: false)
    var updateValue: Int32 = 0
    var text = ""
    var image: UIImage?
    var generation: Int32 = 0
    weak var controller: ItemListController?
    let bump: () -> Void = {
        updateValue += 1
        updatePromise.set(updateValue)
    }
    let arguments = SpaceGramQRToolsArguments(updateText: { value in
        text = value
    }, generate: {
        guard SpaceGramSettings.shared.toolsEnabled else {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            controller?.present(textAlertController(context: context, title: ngI18n("SpaceGram.QR.Title", presentationData.strings.baseLanguageCode), text: ngI18n("SpaceGram.Disabled", presentationData.strings.baseLanguageCode), actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), in: .window(.root))
            return
        }
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let lang = presentationData.strings.baseLanguageCode
            controller?.present(textAlertController(context: context, title: ngI18n("SpaceGram.QR.Title", lang), text: ngI18n("SpaceGram.QR.Empty", lang), actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), in: .window(.root))
            return
        }
        guard let generatedImage = SpaceGramQRGenerator.image(text: trimmedText) else {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let lang = presentationData.strings.baseLanguageCode
            controller?.present(textAlertController(context: context, title: ngI18n("SpaceGram.QR.Title", lang), text: ngI18n("SpaceGram.QR.Failed", lang), actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), in: .window(.root))
            return
        }
        image = generatedImage
        generation += 1
        bump()
    }, share: {
        guard let image else { return }
        let activity = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        if let view = controller?.view {
            activity.popoverPresentationController?.sourceView = view
            activity.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1.0, height: 1.0)
        }
        context.sharedContext.applicationBindings.presentNativeController(activity)
    })
    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, updatePromise.get(), spaceGramToolsEnabledSignal())
    |> map { presentationData, _, enabled -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let listPresentationData = spaceGramItemListPresentationData(presentationData)
        let lang = presentationData.strings.baseLanguageCode
        arguments.textTitle = ngI18n("SpaceGram.QR.Text", lang)
        arguments.placeholder = ngI18n("SpaceGram.QR.Placeholder", lang)
        arguments.generateTitle = ngI18n("SpaceGram.QR.Generate", lang)
        var entries: [SpaceGramQRToolsEntry] = [
            .header(0, 0, ngI18n("SpaceGram.QR.Text", lang)),
            .input(1, 0, text),
            .generate(2, 1, enabled)
        ]
        if let image {
            entries.append(.header(3, 2, ngI18n("SpaceGram.QR.Result", lang)))
            entries.append(.result(4, 2, image, generation))
            entries.append(.share(5, 3, ngI18n("SpaceGram.QR.Share", lang), true))
        }
        let controllerState = ItemListControllerState(presentationData: listPresentationData, title: .text(ngI18n("SpaceGram.QR.Title", lang)), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        return (controllerState, (ItemListNodeState(presentationData: listPresentationData, entries: entries, style: .blocks, animateChanges: true), arguments))
    }
    let itemListController = ItemListController(context: context, state: signal)
    itemListController.navigationPresentation = .default
    controller = itemListController
    return itemListController
}

private final class SpaceGramQRImageItem: ListViewItem, ItemListItem {
    let theme: PresentationTheme
    let image: UIImage
    let sectionId: ItemListSectionId

    init(theme: PresentationTheme, image: UIImage, sectionId: ItemListSectionId) {
        self.theme = theme
        self.image = image
        self.sectionId = sectionId
    }

    func nodeConfiguredForParams(async: @escaping (@escaping () -> Void) -> Void, params: ListViewItemLayoutParams, synchronousLoads: Bool, previousItem: ListViewItem?, nextItem: ListViewItem?, completion: @escaping (ListViewItemNode, @escaping () -> (Signal<Void, NoError>?, (ListViewItemApply) -> Void)) -> Void) {
        async {
            let node = SpaceGramQRImageItemNode()
            let layout = node.layout(item: self, params: params, neighbors: itemListNeighbors(item: self, topItem: previousItem as? ItemListItem, bottomItem: nextItem as? ItemListItem))
            node.contentSize = layout.contentSize
            node.insets = layout.insets
            Queue.mainQueue().async { completion(node, { (nil, { _ in node.apply(item: self, params: params, neighbors: itemListNeighbors(item: self, topItem: previousItem as? ItemListItem, bottomItem: nextItem as? ItemListItem)) }) }) }
        }
    }

    func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, previousItem: ListViewItem?, nextItem: ListViewItem?, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        let neighbors = itemListNeighbors(item: self, topItem: previousItem as? ItemListItem, bottomItem: nextItem as? ItemListItem)
        let layout = (node() as! SpaceGramQRImageItemNode).layout(item: self, params: params, neighbors: neighbors)
        completion(layout, { _ in (node() as? SpaceGramQRImageItemNode)?.apply(item: self, params: params, neighbors: neighbors) })
    }
}

public final class SpaceGramQRImageItemNode: ListViewItemNode {
    private let imageNode = ASImageNode()
    private let backgroundNode = ASDisplayNode()

    public init() {
        super.init(layerBacked: false)
        self.addSubnode(self.backgroundNode)
        self.addSubnode(self.imageNode)
        self.imageNode.contentMode = .scaleAspectFit
    }

    override public func didLoad() {
        super.didLoad()
        // AsyncDisplayKit constructs list nodes off-main. Accessing .layer in
        // init forces a view-backed node to load on that worker and can assert.
        self.imageNode.layer.magnificationFilter = .nearest
        self.imageNode.layer.minificationFilter = .nearest
    }

    fileprivate func layout(item: SpaceGramQRImageItem, params: ListViewItemLayoutParams, neighbors: ItemListNeighbors) -> ListViewItemNodeLayout {
        return ListViewItemNodeLayout(contentSize: CGSize(width: params.width, height: 252.0), insets: itemListNeighborsGroupedInsets(neighbors, params))
    }

    fileprivate func apply(item: SpaceGramQRImageItem, params: ListViewItemLayoutParams, neighbors: ItemListNeighbors) {
        self.backgroundNode.backgroundColor = item.theme.list.itemBlocksBackgroundColor
        self.backgroundNode.frame = CGRect(x: 0.0, y: 0.0, width: params.width, height: 252.0)
        self.imageNode.image = item.image
        self.imageNode.frame = CGRect(x: floor((params.width - 224.0) / 2.0), y: 14.0, width: 224.0, height: 224.0)
    }
}
