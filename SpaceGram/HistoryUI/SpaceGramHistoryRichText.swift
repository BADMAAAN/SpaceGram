import Display
import Foundation
import ItemListUI
import SpaceGramHistoryStorage
import TelegramCore
import TextFormat
import UIKit

func spaceGramHistoryRichText(snapshot: SpaceGramHistorySnapshot, title: String, details: String, presentationData: ItemListPresentationData) -> NSAttributedString {
    let count = snapshot.text.utf16.count
    let entities: [MessageTextEntity] = snapshot.entities.prefix(1024).compactMap { entity in
        let offset = Int(entity.offset)
        let length = Int(entity.length)
        guard offset >= 0, length > 0, offset <= count, length <= count - offset else { return nil }
        let type: MessageTextEntityType
        switch entity.type {
        case "bold": type = .Bold
        case "italic": type = .Italic
        case "code": type = .Code
        case "pre": type = .Pre(language: entity.attributes["language"])
        case "strikethrough": type = .Strikethrough
        case "underline": type = .Underline
        default: return nil // Other entities remain available in saved metadata.
        }
        return MessageTextEntity(range: offset ..< offset + length, type: type)
    }
    let color = presentationData.theme.list.freeTextColor
    let font = Font.regular(15)
    let result = NSMutableAttributedString(string: title + "\n\n", attributes: [.font: font, .foregroundColor: color])
    result.append(stringWithAppliedEntities(snapshot.text, entities: entities, baseColor: color, linkColor: presentationData.theme.list.itemAccentColor, baseFont: font, linkFont: font, boldFont: Font.semibold(15), italicFont: Font.italic(15), boldItalicFont: Font.semiboldItalic(15), fixedFont: Font.monospace(15), blockQuoteFont: font, message: nil))
    if details.hasPrefix(snapshot.text) {
        result.append(NSAttributedString(string: String(details.dropFirst(snapshot.text.count)), attributes: [.font: font, .foregroundColor: color]))
    }
    return result
}
