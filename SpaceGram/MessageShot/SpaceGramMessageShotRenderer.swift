import UIKit

public enum SpaceGramMessageShotMediaKind: Equatable {
    case photo
    case video
    case file
    case voice
    case roundVideo
    case sticker
    case unsupported
}

public struct SpaceGramMessageShotMedia {
    public let kind: SpaceGramMessageShotMediaKind
    public let title: String
    public let image: UIImage?

    public init(kind: SpaceGramMessageShotMediaKind, title: String, image: UIImage?) {
        self.kind = kind
        self.title = title
        self.image = image
    }
}

public struct SpaceGramMessageShotItem {
    public let outgoing: Bool
    public let sender: String
    public let avatarInitials: String
    public let timestamp: String
    public let text: NSAttributedString
    public let replyPreview: String?
    public let media: SpaceGramMessageShotMedia?

    public init(outgoing: Bool, sender: String, avatarInitials: String, timestamp: String, text: NSAttributedString, replyPreview: String?, media: SpaceGramMessageShotMedia?) {
        self.outgoing = outgoing
        self.sender = sender
        self.avatarInitials = avatarInitials
        self.timestamp = timestamp
        self.text = text
        self.replyPreview = replyPreview
        self.media = media
    }
}

public struct SpaceGramMessageShotStyle {
    public let backgroundColor: UIColor
    public let backgroundImage: UIImage?
    public let incomingBubbleColor: UIColor
    public let outgoingBubbleColor: UIColor
    public let incomingTextColor: UIColor
    public let outgoingTextColor: UIColor
    public let secondaryTextColor: UIColor
    public let accentColor: UIColor

    public init(backgroundColor: UIColor, backgroundImage: UIImage? = nil, incomingBubbleColor: UIColor, outgoingBubbleColor: UIColor, incomingTextColor: UIColor, outgoingTextColor: UIColor, secondaryTextColor: UIColor, accentColor: UIColor) {
        self.backgroundColor = backgroundColor
        self.backgroundImage = backgroundImage
        self.incomingBubbleColor = incomingBubbleColor
        self.outgoingBubbleColor = outgoingBubbleColor
        self.incomingTextColor = incomingTextColor
        self.outgoingTextColor = outgoingTextColor
        self.secondaryTextColor = secondaryTextColor
        self.accentColor = accentColor
    }
}

public struct SpaceGramMessageShotOptions {
    public let width: CGFloat
    public let maximumMessages: Int
    public let maximumHeight: CGFloat
    public let maximumPixelCount: CGFloat

    public init(width: CGFloat = 390.0, maximumMessages: Int = 50, maximumHeight: CGFloat = 8192.0, maximumPixelCount: CGFloat = 20_000_000.0) {
        self.width = width
        self.maximumMessages = maximumMessages
        self.maximumHeight = maximumHeight
        self.maximumPixelCount = maximumPixelCount
    }
}

public enum SpaceGramMessageShotError: Error, Equatable {
    case emptySelection
    case invalidDimensions
}

public struct SpaceGramMessageShotLayout: Equatable {
    public let renderedMessageCount: Int
    public let omittedMessageCount: Int
    public let size: CGSize
    public let scale: CGFloat
}

public final class SpaceGramMessageShotRenderer {
    private struct ItemLayout {
        let item: SpaceGramMessageShotItem
        let frame: CGRect
        let avatarFrame: CGRect?
        let senderFrame: CGRect?
        let replyFrame: CGRect?
        let mediaFrame: CGRect?
        let textFrame: CGRect?
        let timestampFrame: CGRect
    }

    public init() {
    }

    public func layout(items: [SpaceGramMessageShotItem], options: SpaceGramMessageShotOptions = SpaceGramMessageShotOptions()) throws -> SpaceGramMessageShotLayout {
        return try self.makeLayout(items: items, options: options).layout
    }

    public func render(items: [SpaceGramMessageShotItem], style: SpaceGramMessageShotStyle, options: SpaceGramMessageShotOptions = SpaceGramMessageShotOptions()) throws -> UIImage {
        let result = try self.makeLayout(items: items, options: options)
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = result.layout.scale
        let renderer = UIGraphicsImageRenderer(size: result.layout.size, format: format)
        return renderer.image { context in
            let graphics = context.cgContext
            style.backgroundColor.setFill()
            graphics.fill(CGRect(origin: .zero, size: result.layout.size))
            if let backgroundImage = style.backgroundImage {
                let imageRatio = backgroundImage.size.width / max(backgroundImage.size.height, 1.0)
                let canvasRatio = result.layout.size.width / max(result.layout.size.height, 1.0)
                let drawSize: CGSize
                if imageRatio > canvasRatio {
                    drawSize = CGSize(width: result.layout.size.height * imageRatio, height: result.layout.size.height)
                } else {
                    drawSize = CGSize(width: result.layout.size.width, height: result.layout.size.width / max(imageRatio, 0.01))
                }
                backgroundImage.draw(in: CGRect(x: (result.layout.size.width - drawSize.width) / 2.0, y: (result.layout.size.height - drawSize.height) / 2.0, width: drawSize.width, height: drawSize.height))
            }

            for entry in result.items {
                let bubbleColor = entry.item.outgoing ? style.outgoingBubbleColor : style.incomingBubbleColor
                bubbleColor.setFill()
                UIBezierPath(roundedRect: entry.frame, cornerRadius: 17.0).fill()

                if let avatarFrame = entry.avatarFrame {
                    style.accentColor.setFill()
                    UIBezierPath(ovalIn: avatarFrame).fill()
                    let initials = entry.item.avatarInitials.isEmpty ? "?" : entry.item.avatarInitials
                    self.draw(initials, in: avatarFrame, font: .systemFont(ofSize: 12.0, weight: .semibold), color: .white, alignment: .center)
                }
                if let senderFrame = entry.senderFrame {
                    self.draw(entry.item.sender, in: senderFrame, font: .systemFont(ofSize: 13.0, weight: .semibold), color: style.accentColor)
                }
                if let replyFrame = entry.replyFrame, let reply = entry.item.replyPreview {
                    style.accentColor.setFill()
                    graphics.fill(CGRect(x: replyFrame.minX, y: replyFrame.minY, width: 2.0, height: replyFrame.height))
                    self.draw(reply, in: replyFrame.insetBy(dx: 8.0, dy: 1.0), font: .systemFont(ofSize: 12.0), color: style.secondaryTextColor)
                }
                if let mediaFrame = entry.mediaFrame, let media = entry.item.media {
                    self.drawMedia(media, in: mediaFrame, style: style)
                }
                if let textFrame = entry.textFrame {
                    let text = NSMutableAttributedString(attributedString: entry.item.text)
                    let fullRange = NSRange(location: 0, length: text.length)
                    let fallback = entry.item.outgoing ? style.outgoingTextColor : style.incomingTextColor
                    text.addAttribute(.foregroundColor, value: fallback, range: fullRange)
                    if text.length > 0 && text.attribute(.font, at: 0, effectiveRange: nil) == nil {
                        text.addAttribute(.font, value: UIFont.systemFont(ofSize: 16.0), range: fullRange)
                    }
                    text.draw(with: textFrame, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
                }
                self.draw(entry.item.timestamp, in: entry.timestampFrame, font: .systemFont(ofSize: 10.0), color: style.secondaryTextColor, alignment: .right)
            }

            if result.layout.omittedMessageCount > 0 {
                let footer = "+(result.layout.omittedMessageCount)"
                self.draw(footer, in: result.footerFrame, font: .systemFont(ofSize: 12.0, weight: .medium), color: style.secondaryTextColor, alignment: .center)
            }
        }
    }

    private func makeLayout(items: [SpaceGramMessageShotItem], options: SpaceGramMessageShotOptions) throws -> (layout: SpaceGramMessageShotLayout, items: [ItemLayout], footerFrame: CGRect) {
        guard !items.isEmpty else {
            throw SpaceGramMessageShotError.emptySelection
        }
        let width = min(max(options.width, 280.0), 1440.0)
        guard options.maximumMessages > 0, options.maximumHeight >= 240.0, options.maximumPixelCount > 0.0 else {
            throw SpaceGramMessageShotError.invalidDimensions
        }

        let limitedItems = Array(items.prefix(options.maximumMessages))
        let horizontalMargin: CGFloat = 12.0
        let verticalMargin: CGFloat = 16.0
        let gap: CGFloat = 6.0
        let avatarSize: CGFloat = 30.0
        let maximumBubbleWidth = width * 0.82
        var y = verticalMargin
        var layouts: [ItemLayout] = []

        for item in limitedItems {
            let showsAvatar = !item.outgoing && !item.sender.isEmpty
            let contentWidth = maximumBubbleWidth - 24.0
            var contentY: CGFloat = 10.0
            var senderFrame: CGRect?
            if !item.sender.isEmpty {
                senderFrame = CGRect(x: 12.0, y: contentY, width: contentWidth, height: 17.0)
                contentY += 19.0
            }
            var replyFrame: CGRect?
            if let reply = item.replyPreview, !reply.isEmpty {
                let replyHeight = min(self.textHeight(reply, font: .systemFont(ofSize: 12.0), width: contentWidth - 8.0), 34.0) + 4.0
                replyFrame = CGRect(x: 12.0, y: contentY, width: contentWidth, height: replyHeight)
                contentY += replyHeight + 5.0
            }
            var mediaFrame: CGRect?
            if item.media != nil {
                let mediaHeight = min(210.0, contentWidth * 0.68)
                mediaFrame = CGRect(x: 12.0, y: contentY, width: contentWidth, height: mediaHeight)
                contentY += mediaHeight + 7.0
            }
            var textFrame: CGRect?
            if item.text.length > 0 {
                let textHeight = min(self.attributedTextHeight(item.text, width: contentWidth), 900.0)
                textFrame = CGRect(x: 12.0, y: contentY, width: contentWidth, height: textHeight)
                contentY += textHeight + 4.0
            }
            let timestampFrame = CGRect(x: 12.0, y: contentY, width: contentWidth, height: 13.0)
            contentY += 13.0 + 9.0
            let bubbleHeight = max(contentY, 44.0)
            let bubbleX = item.outgoing ? width - horizontalMargin - maximumBubbleWidth : horizontalMargin + (showsAvatar ? avatarSize + 6.0 : 0.0)
            let bubbleFrame = CGRect(x: bubbleX, y: y, width: maximumBubbleWidth, height: bubbleHeight)
            let proposedBottom = bubbleFrame.maxY + verticalMargin
            if proposedBottom > options.maximumHeight && !layouts.isEmpty {
                break
            }
            let avatarFrame = showsAvatar ? CGRect(x: horizontalMargin, y: bubbleFrame.maxY - avatarSize, width: avatarSize, height: avatarSize) : nil
            let translated: (CGRect?) -> CGRect? = { frame in
                frame.map { $0.offsetBy(dx: bubbleFrame.minX, dy: bubbleFrame.minY) }
            }
            layouts.append(ItemLayout(item: item, frame: bubbleFrame, avatarFrame: avatarFrame, senderFrame: translated(senderFrame), replyFrame: translated(replyFrame), mediaFrame: translated(mediaFrame), textFrame: translated(textFrame), timestampFrame: timestampFrame.offsetBy(dx: bubbleFrame.minX, dy: bubbleFrame.minY)))
            y = bubbleFrame.maxY + gap
        }

        let omitted = items.count - layouts.count
        let footerHeight: CGFloat = omitted > 0 ? 26.0 : 0.0
        let finalHeight = min(max(y + verticalMargin + footerHeight, 120.0), options.maximumHeight)
        let size = CGSize(width: width, height: finalHeight)
        let deviceScale = min(max(UIScreen.main.scale, 1.0), 3.0)
        let safeScale = min(deviceScale, sqrt(options.maximumPixelCount / max(size.width * size.height, 1.0)))
        guard safeScale > 0.0, safeScale.isFinite else {
            throw SpaceGramMessageShotError.invalidDimensions
        }
        let footerFrame = CGRect(x: horizontalMargin, y: finalHeight - footerHeight - 4.0, width: width - horizontalMargin * 2.0, height: footerHeight)
        return (SpaceGramMessageShotLayout(renderedMessageCount: layouts.count, omittedMessageCount: omitted, size: size, scale: safeScale), layouts, footerFrame)
    }

    private func attributedTextHeight(_ text: NSAttributedString, width: CGFloat) -> CGFloat {
        let mutable = NSMutableAttributedString(attributedString: text)
        if mutable.length > 0 && mutable.attribute(.font, at: 0, effectiveRange: nil) == nil {
            mutable.addAttribute(.font, value: UIFont.systemFont(ofSize: 16.0), range: NSRange(location: 0, length: mutable.length))
        }
        return ceil(mutable.boundingRect(with: CGSize(width: width, height: 1000.0), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height)
    }

    private func textHeight(_ text: String, font: UIFont, width: CGFloat) -> CGFloat {
        return ceil((text as NSString).boundingRect(with: CGSize(width: width, height: 100.0), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font], context: nil).height)
    }

    private func draw(_ string: String, in frame: CGRect, font: UIFont, color: UIColor, alignment: NSTextAlignment = .left) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        (string as NSString).draw(with: frame, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph], context: nil)
    }

    private func drawMedia(_ media: SpaceGramMessageShotMedia, in frame: CGRect, style: SpaceGramMessageShotStyle) {
        guard let graphics = UIGraphicsGetCurrentContext() else {
            return
        }
        graphics.saveGState()
        defer { graphics.restoreGState() }
        UIBezierPath(roundedRect: frame, cornerRadius: 12.0).addClip()
        if let image = media.image {
            let imageRatio = image.size.width / max(image.size.height, 1.0)
            let frameRatio = frame.width / max(frame.height, 1.0)
            let drawSize: CGSize
            if imageRatio > frameRatio {
                drawSize = CGSize(width: frame.height * imageRatio, height: frame.height)
            } else {
                drawSize = CGSize(width: frame.width, height: frame.width / max(imageRatio, 0.01))
            }
            image.draw(in: CGRect(x: frame.midX - drawSize.width / 2.0, y: frame.midY - drawSize.height / 2.0, width: drawSize.width, height: drawSize.height))
        } else {
            style.secondaryTextColor.withAlphaComponent(0.12).setFill()
            UIRectFill(frame)
            let symbol: String
            switch media.kind {
            case .photo: symbol = "photo"
            case .video, .roundVideo: symbol = "video"
            case .file: symbol = "doc"
            case .voice: symbol = "waveform"
            case .sticker: symbol = "face.smiling"
            case .unsupported: symbol = "questionmark.square.dashed"
            }
            if let icon = UIImage(systemName: symbol)?.withTintColor(style.secondaryTextColor, renderingMode: .alwaysOriginal) {
                let iconSize = CGSize(width: 32.0, height: 32.0)
                icon.draw(in: CGRect(x: frame.midX - iconSize.width / 2.0, y: frame.midY - 28.0, width: iconSize.width, height: iconSize.height))
            }
        }
        if !media.title.isEmpty {
            let titleFrame = CGRect(x: frame.minX + 8.0, y: frame.maxY - 30.0, width: frame.width - 16.0, height: 22.0)
            UIColor.black.withAlphaComponent(0.55).setFill()
            UIBezierPath(roundedRect: titleFrame.insetBy(dx: -4.0, dy: -2.0), cornerRadius: 6.0).fill()
            self.draw(media.title, in: titleFrame, font: .systemFont(ofSize: 12.0, weight: .medium), color: .white)
        }
    }
}
