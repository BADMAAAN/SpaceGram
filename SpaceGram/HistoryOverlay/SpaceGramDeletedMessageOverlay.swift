import Foundation
import Postbox
import SpaceGramHistoryStorage
import SwiftSignalKit
import TelegramCore

public final class SpaceGramDeletedMessageAttribute: MessageAttribute {
    public let originalMessageId: MessageId

    public init(originalMessageId: MessageId) {
        self.originalMessageId = originalMessageId
    }

    public required init(decoder: PostboxDecoder) {
        self.originalMessageId = MessageId(
            peerId: PeerId(decoder.decodeInt64ForKey("p", orElse: 0)),
            namespace: decoder.decodeInt32ForKey("n", orElse: 0),
            id: decoder.decodeInt32ForKey("i", orElse: 0)
        )
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeInt64(self.originalMessageId.peerId.toInt64(), forKey: "p")
        encoder.encodeInt32(self.originalMessageId.namespace, forKey: "n")
        encoder.encodeInt32(self.originalMessageId.id, forKey: "i")
    }
}

public struct SpaceGramDeletedMessageOverlayItem {
    public let originalMessageId: MessageId
    public let threadId: Int64?
    public let snapshot: SpaceGramHistorySnapshot
    public let author: Peer?
    public let chatPeer: Peer?
    public let hasArchivedMedia: Bool
    public let stableVersion: UInt32

    public init(originalMessageId: MessageId, threadId: Int64?, snapshot: SpaceGramHistorySnapshot, author: Peer?, chatPeer: Peer?, hasArchivedMedia: Bool, stableVersion: UInt32) {
        self.originalMessageId = originalMessageId
        self.threadId = threadId
        self.snapshot = snapshot
        self.author = author
        self.chatPeer = chatPeer
        self.hasArchivedMedia = hasArchivedMedia
        self.stableVersion = stableVersion
    }

    public var timestamp: Int32 {
        return Int32(clamping: self.snapshot.originalMessageTimestamp)
    }

    public func makeMessage(accountPeerId: PeerId, deletedLabel: String, archivedMediaLabel: String, missingMediaLabel: String) -> Message {
        var text = self.snapshot.text
        var entities = self.snapshot.entities.compactMap { spaceGramMessageEntity($0, textLength: text.utf16.count) }

        if !text.isEmpty {
            text.append("\n")
        }
        let indicatorStart = text.utf16.count
        text.append("🗑 ")
        text.append(deletedLabel)
        entities.append(MessageTextEntity(range: indicatorStart ..< text.utf16.count, type: .Italic))

        if !self.snapshot.media.isEmpty {
            text.append("\n")
            let mediaStart = text.utf16.count
            text.append(self.hasArchivedMedia ? archivedMediaLabel : missingMediaLabel)
            entities.append(MessageTextEntity(range: mediaStart ..< text.utf16.count, type: .Italic))
        }

        let localId = Int32(bitPattern: UInt32(bitPattern: self.originalMessageId.id) ^ 0x80000000)
        let localMessageId = MessageId(peerId: self.originalMessageId.peerId, namespace: Namespaces.Message.Local, id: localId)
        var peers = SimpleDictionary<PeerId, Peer>()
        if let chatPeer = self.chatPeer {
            peers[chatPeer.id] = chatPeer
        }
        if let author = self.author {
            peers[author.id] = author
        }
        let incoming = self.author?.id != accountPeerId
        return Message(
            stableId: UInt32(bitPattern: localId),
            stableVersion: self.stableVersion,
            id: localMessageId,
            globallyUniqueId: nil,
            groupingKey: nil,
            groupInfo: nil,
            threadId: self.threadId,
            timestamp: self.timestamp,
            flags: incoming ? [.Incoming] : [],
            tags: [],
            globalTags: [],
            localTags: [],
            customTags: [],
            forwardInfo: nil,
            author: self.author,
            text: text,
            attributes: [
                TextEntitiesMessageAttribute(entities: entities),
                SpaceGramDeletedMessageAttribute(originalMessageId: self.originalMessageId),
            ],
            media: [],
            peers: peers,
            associatedMessages: SimpleDictionary<MessageId, Message>(),
            associatedMessageIds: [],
            associatedMedia: [:],
            associatedThreadInfo: nil,
            associatedStories: [:]
        )
    }
}

public enum SpaceGramDeletedOverlayPolicy {
    public static func includes(timestamp: Int32, lowerTimestamp: Int32?, upperTimestamp: Int32?, canExtendEarlier: Bool, canExtendLater: Bool) -> Bool {
        if let lowerTimestamp, timestamp < lowerTimestamp, !canExtendEarlier {
            return false
        }
        if let upperTimestamp, timestamp > upperTimestamp, !canExtendLater {
            return false
        }
        return true
    }
}

public func spaceGramDeletedMessageOverlay(postbox: Postbox, peerId: PeerId, threadId: Int64?) -> Signal<[SpaceGramDeletedMessageOverlayItem], NoError> {
    let key = PostboxViewKey.orderedItemList(id: SpaceGramHistoryCollection.id)
    return postbox.combinedView(keys: [key])
    |> mapToSignal { _ in
        return postbox.transaction { transaction -> [SpaceGramDeletedMessageOverlayItem] in
            let chatPeer = transaction.getPeer(peerId)
            return SpaceGramHistoryStore.listRecords(transaction: transaction).records.compactMap { record in
                guard record.key.peerId == peerId.toInt64(), record.threadId == threadId,
                      let deleteEvent = record.events.last(where: { $0.type == .delete }),
                      let snapshot = SpaceGramHistoryPresentationModel.deletedSnapshot(record) else {
                    return nil
                }
                let originalMessageId = MessageId(peerId: peerId, namespace: record.key.namespace, id: record.key.id)
                let author = snapshot.authorPeerId.flatMap { transaction.getPeer(PeerId($0)) }
                return SpaceGramDeletedMessageOverlayItem(
                    originalMessageId: originalMessageId,
                    threadId: record.threadId,
                    snapshot: snapshot,
                    author: author,
                    chatPeer: chatPeer,
                    hasArchivedMedia: !(deleteEvent.mediaAssetIds ?? []).isEmpty,
                    stableVersion: UInt32(truncatingIfNeeded: deleteEvent.observedTimestamp)
                )
            }.sorted { lhs, rhs in
                if lhs.timestamp != rhs.timestamp {
                    return lhs.timestamp < rhs.timestamp
                }
                return lhs.originalMessageId.id < rhs.originalMessageId.id
            }
        }
    }
}

private func spaceGramMessageEntity(_ entity: SpaceGramHistoryEntity, textLength: Int) -> MessageTextEntity? {
    let lower = Int(entity.offset)
    let upper = lower + Int(entity.length)
    guard lower >= 0, upper >= lower, upper <= textLength else {
        return nil
    }
    let type: MessageTextEntityType
    switch entity.type {
    case "mention": type = .Mention
    case "hashtag": type = .Hashtag
    case "botCommand": type = .BotCommand
    case "url": type = .Url
    case "email": type = .Email
    case "bold": type = .Bold
    case "italic": type = .Italic
    case "code": type = .Code
    case "pre": type = .Pre(language: entity.attributes["language"])
    case "textUrl":
        guard let url = entity.attributes["url"] else { return nil }
        type = .TextUrl(url: url)
    case "textMention":
        guard let value = entity.attributes["peerId"], let peerId = Int64(value) else { return nil }
        type = .TextMention(peerId: PeerId(peerId))
    case "phoneNumber": type = .PhoneNumber
    case "strikethrough": type = .Strikethrough
    case "blockQuote": type = .BlockQuote(isCollapsed: entity.attributes["isCollapsed"] == "true")
    case "underline": type = .Underline
    case "bankCard": type = .BankCard
    case "spoiler": type = .Spoiler
    case "customEmoji":
        guard let value = entity.attributes["fileId"], let fileId = Int64(value) else { return nil }
        type = .CustomEmoji(stickerPack: nil, fileId: fileId)
    case "formattedDate":
        guard let value = entity.attributes["date"], let date = Int32(value) else { return nil }
        let format = entity.attributes["format"].flatMap(Int32.init).map { MessageTextEntityType.DateTimeFormat(rawValue: $0) }
        type = .FormattedDate(format: format, date: date)
    case "custom":
        guard let value = entity.attributes["type"], let customType = Int32(value) else { return nil }
        type = .Custom(type: customType)
    default:
        return nil
    }
    return MessageTextEntity(range: lower ..< upper, type: type)
}
