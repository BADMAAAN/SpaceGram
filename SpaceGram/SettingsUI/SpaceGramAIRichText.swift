import Foundation
import TextFormat
import UIKit

// This bounded renderer runs only for completed assistant messages. Streaming
// chunks remain plain text, so partial Markdown never reaches the parser.
private let spaceGramInlinePattern = try! NSRegularExpression(pattern: #"\[([^\]]+)\]\((https?://[^\s)]+)\)|\*\*([^*\n]+)\*\*|__([^_\n]+)__|(?<!\*)\*([^*\n]+)\*(?!\*)|(?<!_)_([^_\n]+)_(?!_)|`([^`\n]+)`"#)

func spaceGramRenderAIResponse(_ source: String, color: UIColor, linkColor: UIColor) -> NSAttributedString {
    let body = UIFont.systemFont(ofSize: 15)
    if source.utf16.count > 100_000 {
        return NSAttributedString(string: source, attributes: [.font: body, .foregroundColor: color])
    }
    let bold = UIFont.boldSystemFont(ofSize: 15)
    let italic = UIFont.italicSystemFont(ofSize: 15)
    let code = UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)
    let result = NSMutableAttributedString(string: "")
    var fenced = false
    for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
        let value = String(line)
        if value.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
            fenced.toggle()
            continue
        }
        if result.length > 0 { result.append(NSAttributedString(string: "\n", attributes: [.font: body, .foregroundColor: color])) }
        if fenced {
            result.append(NSAttributedString(string: value, attributes: [.font: code, .foregroundColor: color]))
            continue
        }
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        let isHeading = trimmed.hasPrefix("# ") || trimmed.hasPrefix("## ") || trimmed.hasPrefix("### ")
        let isBullet = trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ")
        let prefix = isHeading ? String(trimmed.drop(while: { $0 == "#" || $0 == " " })) : (isBullet ? "• " + String(trimmed.dropFirst(2)) : value)
        let text = prefix as NSString
        let matches = spaceGramInlinePattern.matches(in: prefix, range: NSRange(location: 0, length: text.length))
        var cursor = 0
        for match in matches {
            if match.range.location > cursor {
                result.append(NSAttributedString(string: text.substring(with: NSRange(location: cursor, length: match.range.location - cursor)), attributes: [.font: isHeading ? bold : body, .foregroundColor: color]))
            }
            let index = (1 ..< match.numberOfRanges).first { match.range(at: $0).location != NSNotFound } ?? 0
            let display = text.substring(with: match.range(at: index))
            var attributes: [NSAttributedString.Key: Any] = [.font: body, .foregroundColor: color]
            if index == 1 {
                attributes[.foregroundColor] = linkColor
                attributes[NSAttributedString.Key(rawValue: TelegramTextAttributes.URL)] = text.substring(with: match.range(at: 2))
            } else if index == 3 || index == 4 || isHeading {
                attributes[.font] = bold
            } else if index == 5 || index == 6 {
                attributes[.font] = italic
            } else if index == 7 {
                attributes[.font] = code
            }
            result.append(NSAttributedString(string: display, attributes: attributes))
            cursor = NSMaxRange(match.range)
        }
        if cursor < text.length {
            result.append(NSAttributedString(string: text.substring(from: cursor), attributes: [.font: isHeading ? bold : body, .foregroundColor: color]))
        }
    }
    return result
}
