import AccountContext
import AsyncDisplayKit
import CoreImage
import Display
import Foundation
import ItemListUI
import QwengramStrings
import PresentationDataUtils
import QwengramSettings
import QwengramSettingsSignal
import SwiftSignalKit
import TelegramPresentationData
import UIKit

private enum QwengramQRToolsEntry: ItemListNodeEntry {
    case header(Int32, Int32, String)
    case input(Int32, Int32, String)
    case generate(Int32, Int32, Bool)
    case result(Int32, Int32, UIImage, Int32)

    var section: ItemListSectionId {
        switch self { case let .header(_, section, _), let .input(_, section, _), let .generate(_, section, _), let .result(_, section, _, _): return section }
    }

    var stableId: Int32 {
        switch self { case let .header(id, _, _), let .input(id, _, _), let .generate(id, _, _), let .result(id, _, _, _): return id }
    }

    static func == (lhs: QwengramQRToolsEntry, rhs: QwengramQRToolsEntry) -> Bool {
        switch (lhs, rhs) {
        case let (.header(lId, lSection, lText), .header(rId, rSection, rText)):
            return lId == rId && lSection == rSection && lText == rText
        case let (.input(lId, lSection, lText), .input(rId, rSection, rText)):
            return lId == rId && lSection == rSection && lText == rText
        case let (.generate(lId, lSection, lEnabled), .generate(rId, rSection, rEnabled)):
            return lId == rId && lSection == rSection && lEnabled == rEnabled
        case let (.result(lId, lSection, _, lGeneration), .result(rId, rSection, _, rGeneration)):
            return lId == rId && lSection == rSection && lGeneration == rGeneration
        default:
            return false
        }
    }

    static func < (lhs: QwengramQRToolsEntry, rhs: QwengramQRToolsEntry) -> Bool { lhs.stableId < rhs.stableId }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! QwengramQRToolsArguments
        switch self {
        case let .header(_, section, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: section)
        case let .input(_, section, text):
            return ItemListSingleLineInputItem(presentationData: presentationData, systemStyle: .glass, title: NSAttributedString(string: "Text", textColor: presentationData.theme.list.itemPrimaryTextColor), text: text, placeholder: "Enter text", type: .regular(capitalization: false, autocorrection: false), clearType: .onFocus, sectionId: section, textUpdated: arguments.updateText, action: {})
        case let .generate(_, section, enabled):
            return ItemListActionItem(presentationData: presentationData, systemStyle: .glass, title: "Generate QR", kind: enabled ? .generic : .disabled, alignment: .natural, sectionId: section, style: .blocks, action: arguments.generate)
        case let .result(_, section, image, _):
            return QwengramQRImageItem(theme: presentationData.theme, image: image, sectionId: section)
        }
    }
}

private final class QwengramQRToolsArguments {
    let updateText: (String) -> Void
    let generate: () -> Void

    init(updateText: @escaping (String) -> Void, generate: @escaping () -> Void) {
        self.updateText = updateText
        self.generate = generate
    }
}

private func qwengramQRImage(text: String) -> UIImage? {
    guard let data = text.data(using: .utf8), !data.isEmpty,
          let filter = CIFilter(name: "CIQRCodeGenerator") else {
        return nil
    }
    filter.setValue(data, forKey: "inputMessage")
    filter.setValue("M", forKey: "inputCorrectionLevel")
    guard let output = filter.outputImage else {
        return nil
    }
    let scaled = output.transformed(by: CGAffineTransform(scaleX: 8.0, y: 8.0))
    guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else {
        return nil
    }
    return UIImage(cgImage: cgImage)
}

public func qwengramQRToolsController(context: AccountContext) -> ViewController {
    let updatePromise = ValuePromise<Int32>(0, ignoreRepeated: false)
    var updateValue: Int32 = 0
    var text = ""
    var image: UIImage?
    var generation: Int32 = 0
    var controller: ItemListController?
    let bump: () -> Void = {
        updateValue += 1
        updatePromise.set(updateValue)
    }
    let arguments = QwengramQRToolsArguments(updateText: { value in
        text = value
    }, generate: {
        guard QwengramSettings.shared.toolsEnabled else {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            controller?.present(textAlertController(context: context, title: "QR Tools", text: ngI18n("Qwengram.Disabled", presentationData.strings.baseLanguageCode), actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), in: .window(.root))
            return
        }
        guard !text.isEmpty else {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            controller?.present(textAlertController(context: context, title: "QR Tools", text: "Enter text to generate a QR code.", actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), in: .window(.root))
            return
        }
        guard let generatedImage = qwengramQRImage(text: text) else {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            controller?.present(textAlertController(context: context, title: "QR Tools", text: "Unable to generate a QR code for this text.", actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), in: .window(.root))
            return
        }
        image = generatedImage
        generation += 1
        bump()
    })
    let signal = combineLatest(queue: .mainQueue(), context.sharedContext.presentationData, updatePromise.get(), qwengramToolsEnabledSignal())
    |> map { presentationData, _, enabled -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let listPresentationData = ItemListPresentationData(presentationData)
        var entries: [QwengramQRToolsEntry] = [
            .header(0, 0, "Text"),
            .input(1, 0, text),
            .generate(2, 1, enabled)
        ]
        if let image {
            entries.append(.header(3, 2, "Result"))
            entries.append(.result(4, 2, image, generation))
        }
        let controllerState = ItemListControllerState(presentationData: listPresentationData, title: .text("QR Tools"), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        return (controllerState, (ItemListNodeState(presentationData: listPresentationData, entries: entries, style: .blocks, animateChanges: true), arguments))
    }
    let itemListController = ItemListController(context: context, state: signal)
    itemListController.navigationPresentation = .default
    controller = itemListController
    return itemListController
}

private final class QwengramQRImageItem: ListViewItem, ItemListItem {
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
            let node = QwengramQRImageItemNode()
            let layout = node.layout(item: self, params: params, neighbors: itemListNeighbors(item: self, topItem: previousItem as? ItemListItem, bottomItem: nextItem as? ItemListItem))
            node.contentSize = layout.contentSize
            node.insets = layout.insets
            Queue.mainQueue().async { completion(node, { (nil, { _ in node.apply(item: self, params: params, neighbors: itemListNeighbors(item: self, topItem: previousItem as? ItemListItem, bottomItem: nextItem as? ItemListItem)) }) }) }
        }
    }

    func updateNode(async: @escaping (@escaping () -> Void) -> Void, node: @escaping () -> ListViewItemNode, params: ListViewItemLayoutParams, previousItem: ListViewItem?, nextItem: ListViewItem?, animation: ListViewItemUpdateAnimation, completion: @escaping (ListViewItemNodeLayout, @escaping (ListViewItemApply) -> Void) -> Void) {
        let neighbors = itemListNeighbors(item: self, topItem: previousItem as? ItemListItem, bottomItem: nextItem as? ItemListItem)
        let layout = (node() as! QwengramQRImageItemNode).layout(item: self, params: params, neighbors: neighbors)
        completion(layout, { _ in (node() as? QwengramQRImageItemNode)?.apply(item: self, params: params, neighbors: neighbors) })
    }
}

private final class QwengramQRImageItemNode: ListViewItemNode {
    private let imageNode = ASImageNode()
    private let backgroundNode = ASDisplayNode()

    init() {
        super.init(layerBacked: false)
        self.addSubnode(self.backgroundNode)
        self.addSubnode(self.imageNode)
        self.imageNode.contentMode = .scaleAspectFit
        self.imageNode.layer.magnificationFilter = .nearest
        self.imageNode.layer.minificationFilter = .nearest
    }

    func layout(item: QwengramQRImageItem, params: ListViewItemLayoutParams, neighbors: ItemListNeighbors) -> ListViewItemNodeLayout {
        return ListViewItemNodeLayout(contentSize: CGSize(width: params.width, height: 252.0), insets: itemListNeighborsGroupedInsets(neighbors, params))
    }

    func apply(item: QwengramQRImageItem, params: ListViewItemLayoutParams, neighbors: ItemListNeighbors) {
        self.backgroundNode.backgroundColor = item.theme.list.itemBlocksBackgroundColor
        self.backgroundNode.frame = CGRect(x: 0.0, y: 0.0, width: params.width, height: 252.0)
        self.imageNode.image = item.image
        self.imageNode.frame = CGRect(x: floor((params.width - 224.0) / 2.0), y: 14.0, width: 224.0, height: 224.0)
    }
}
