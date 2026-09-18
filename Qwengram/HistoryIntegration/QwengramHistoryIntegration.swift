import Foundation
import Postbox
import QwengramHistoryStorage
import QwengramMediaArchive
import QwengramSettings
import SwiftSignalKit

// Compiled inside TelegramCore. Never retain the transaction or re-enter message writes.
func qwengramBeforeMessageUpdate(transaction: Transaction, old: Message, new: StoreMessage, source: MessageUpdateSource) {
    guard QwengramSettings.shared.captureEditedMessages else {
        return
    }
    // Local -> cloud identity/resource reconciliation is not a message edit.
    guard old.id.namespace == Namespaces.Message.Cloud,
          old.id.peerId.namespace != Namespaces.Peer.SecretChat,
          case let .Id(newId) = new.id, newId == old.id else {
        return
    }
    // Expiration replaces media with a tombstone. Do not archive TTL cleanup as an edit.
    guard !old.media.contains(where: { $0 is TelegramMediaExpiredContent }),
          !new.media.contains(where: { $0 is TelegramMediaExpiredContent }) else {
        return
    }
    let newEntities = qwengramHistoryEntities(new.attributes)
    let mediaChanged = !qwengramHistoryMediaEqual(qwengramHistoryContentMedia(old.media), qwengramHistoryContentMedia(new.media))
    guard old.text != new.text || qwengramHistoryEntities(old.attributes) != newEntities || mediaChanged else {
        return
    }
    let snapshot = qwengramHistorySnapshot(old)

    do {
        let key = QwengramHistoryMessageKey(peerId: old.id.peerId.toInt64(), namespace: old.id.namespace, id: old.id.id)
        var record = try QwengramHistoryStore.load(transaction: transaction, key: key) ?? QwengramHistoryRecord(key: key, threadId: old.threadId)
        guard record.nextRevision < Int64.max else {
            throw QwengramHistoryStorageError.invalidRevisionSequence
        }
        let number = record.nextRevision
        let observedTimestamp = Int64(Date().timeIntervalSince1970)
        record.threadId = old.threadId
        record.revisions.append(QwengramHistoryRevision(number: number, observedTimestamp: observedTimestamp, snapshot: snapshot))
        record.events.append(QwengramHistoryEvent(type: .edit, source: source.rawValue, reason: source == .addMessages ? .syncDetectedEdit : .edit, observedTimestamp: observedTimestamp, revisionNumber: number))
        record.nextRevision += 1
        // One validated write: an event can never be persisted without its revision.
        try QwengramHistoryStore.upsert(transaction: transaction, record: record)
    } catch {
        // Do not log message content or decoder errors (which may contain private values).
        NSLog("QwengramHistory: archive write failed; Telegram message write will continue")
    }
}

enum QwengramHistoryServerDeleteSource: String {
    case updateDeleteMessages
    case updateDeleteChannelMessages
    case channelDifference
}

// A server deletion confirms disappearance, not who initiated it.
// Called in the live transaction immediately before Telegram's normal deletion.
func qwengramBeforeServerDelete(postbox: Postbox, transaction: Transaction, ids: [MessageId], source: QwengramHistoryServerDeleteSource) {
    guard QwengramSettings.shared.captureDeletedMessages else {
        return
    }
    var seen = Set<MessageId>()
    for id in ids {
        guard seen.insert(id).inserted,
              id.namespace == Namespaces.Message.Cloud,
              id.peerId.namespace == Namespaces.Peer.CloudUser || id.peerId.namespace == Namespaces.Peer.CloudGroup || id.peerId.namespace == Namespaces.Peer.CloudChannel,
              let old = transaction.getMessage(id) else {
            // Local deletes and repeated server echoes have no live OLD to capture.
            continue
        }
        // A server update confirms disappearance, including timed messages; its
        // cause is unknown. Never attribute it to a sender or infer expiration.
        guard !old.media.contains(where: { media in
                  if media is TelegramMediaExpiredContent {
                      return true
                  }
                  if let action = media as? TelegramMediaAction, case .historyCleared = action.action {
                      return true
                  }
                  return false
              }) else {
            continue
        }
        do {
            let key = QwengramHistoryMessageKey(peerId: id.peerId.toInt64(), namespace: id.namespace, id: id.id)
            var record = try QwengramHistoryStore.load(transaction: transaction, key: key) ?? QwengramHistoryRecord(key: key, threadId: old.threadId)
            guard record.nextRevision < Int64.max else {
                throw QwengramHistoryStorageError.invalidRevisionSequence
            }
            let number = record.nextRevision
            let observedTimestamp = Int64(Date().timeIntervalSince1970)
            record.threadId = old.threadId
            record.revisions.append(QwengramHistoryRevision(number: number, observedTimestamp: observedTimestamp, snapshot: qwengramHistorySnapshot(old)))
            let captures = qwengramPinMessageMedia(postbox: postbox, message: old)
            var event = QwengramHistoryEvent(type: .delete, source: source.rawValue, reason: .serverDelete, observedTimestamp: observedTimestamp, revisionNumber: number)
            event.mediaCaptureId = captures.isEmpty ? nil : UUID().uuidString
            record.events.append(event)
            record.nextRevision += 1
            try QwengramHistoryStore.upsert(transaction: transaction, record: record)
            if let captureId = event.mediaCaptureId {
                qwengramStoreMessageMedia(postbox: postbox, key: key, captureId: captureId, captures: captures)
            }
        } catch {
            // Continue with the remaining IDs and the caller's ordinary deletion.
            NSLog("QwengramHistory: archive write failed; Telegram message deletion will continue")
        }
    }
}

func qwengramHistorySnapshot(_ message: Message) -> QwengramHistorySnapshot {
    var snapshot = QwengramHistorySnapshot(text: message.text, originalMessageTimestamp: Int64(message.timestamp))
    snapshot.authorPeerId = message.author?.id.toInt64()
    snapshot.entities = qwengramHistoryEntities(message.attributes)
    for attribute in message.attributes {
        if let edited = attribute as? EditedMessageAttribute {
            snapshot.serverEditTimestamp = Int64(edited.date)
        } else if let reply = attribute as? ReplyMessageAttribute {
            snapshot.replyMetadata = qwengramHistoryMessageId(reply.messageId)
            snapshot.replyMetadata?["quoteText"] = reply.quote?.text
        }
    }
    if let forward = message.forwardInfo {
        var metadata: [String: String] = ["date": String(forward.date)]
        metadata["authorPeerId"] = forward.author.map { String($0.id.toInt64()) }
        metadata["sourcePeerId"] = forward.source.map { String($0.id.toInt64()) }
        metadata["authorSignature"] = forward.authorSignature
        if let id = forward.sourceMessageId {
            metadata.merge(qwengramHistoryMessageId(id)) { _, new in new }
        }
        snapshot.forwardMetadata = metadata
    }
    if let threadId = message.threadId {
        snapshot.threadMetadata = ["threadId": String(threadId)]
    }
    snapshot.media = qwengramHistoryContentMedia(message.media)
    // Descriptive details belong to the snapshot, but not the edit comparison:
    // downloads/sync may fill these in without changing the attachment.
    for media in message.media {
        if let file = media as? TelegramMediaFile,
           let index = snapshot.media.firstIndex(where: { $0.type == "file" && $0.identifiers == qwengramHistoryMediaId(file.fileId) }) {
            snapshot.media[index].filename = file.fileName
            snapshot.media[index].size = file.size
            for attribute in file.attributes {
                switch attribute {
                case let .Video(duration, size, _, _, _, _):
                    snapshot.media[index].duration = duration
                    snapshot.media[index].width = size.width
                    snapshot.media[index].height = size.height
                case let .Audio(_, duration, _, _, _):
                    snapshot.media[index].duration = Double(duration)
                default:
                    break
                }
            }
        }
    }
    return snapshot
}

private func qwengramHistoryMessageId(_ id: MessageId) -> [String: String] {
    return ["peerId": String(id.peerId.toInt64()), "namespace": String(id.namespace), "id": String(id.id)]
}

private func qwengramHistoryMediaId(_ id: MediaId) -> [String: String] {
    return ["namespace": String(id.namespace), "id": String(id.id)]
}

// Explicit content allowlist. Never serialize arbitrary attributes or media resources.
private func qwengramHistoryContentMedia(_ media: [Media]) -> [QwengramHistoryMediaMetadata] {
    return media.compactMap { media in
        if let image = media as? TelegramMediaImage {
            var result = QwengramHistoryMediaMetadata(type: "image")
            result.identifiers = qwengramHistoryMediaId(image.imageId)
            return result
        } else if let file = media as? TelegramMediaFile {
            var result = QwengramHistoryMediaMetadata(type: "file")
            result.identifiers = qwengramHistoryMediaId(file.fileId)
            return result
        } else if let contact = media as? TelegramMediaContact {
            var result = QwengramHistoryMediaMetadata(type: "contact")
            result.identifiers = ["firstName": contact.firstName, "lastName": contact.lastName, "phoneNumber": contact.phoneNumber]
            result.text = contact.vCardData
            return result
        }
        // Web previews, polls/results, locations, service/unsupported media
        // can change through refreshes. They are outside this conservative V1 filter.
        return nil
    }
}

// Rendering can reorder embedded and referenced media. Match each occurrence once.
private func qwengramHistoryMediaEqual(_ lhs: [QwengramHistoryMediaMetadata], _ rhs: [QwengramHistoryMediaMetadata]) -> Bool {
    guard lhs.count == rhs.count else {
        return false
    }
    var unmatched = rhs
    for media in lhs {
        guard let index = unmatched.firstIndex(of: media) else {
            return false
        }
        unmatched.remove(at: index)
    }
    return true
}

private func qwengramHistoryEntities(_ attributes: [MessageAttribute]) -> [QwengramHistoryEntity] {
    return attributes.compactMap { $0 as? TextEntitiesMessageAttribute }.flatMap { attribute in
        attribute.entities.map { entity in
            let type: String
            var attributes: [String: String] = [:]
            switch entity.type {
            case .Unknown: type = "unknown"
            case .Mention: type = "mention"
            case .Hashtag: type = "hashtag"
            case .BotCommand: type = "botCommand"
            case .Url: type = "url"
            case .Email: type = "email"
            case .Bold: type = "bold"
            case .Italic: type = "italic"
            case .Code: type = "code"
            case let .Pre(language):
                type = "pre"
                attributes["language"] = language
            case let .TextUrl(url):
                type = "textUrl"
                attributes["url"] = url
            case let .TextMention(peerId):
                type = "textMention"
                attributes["peerId"] = String(peerId.toInt64())
            case .PhoneNumber: type = "phoneNumber"
            case .Strikethrough: type = "strikethrough"
            case let .BlockQuote(isCollapsed):
                type = "blockQuote"
                attributes["isCollapsed"] = String(isCollapsed)
            case .Underline: type = "underline"
            case .BankCard: type = "bankCard"
            case .Spoiler: type = "spoiler"
            case let .CustomEmoji(_, fileId):
                type = "customEmoji"
                attributes["fileId"] = String(fileId)
            case let .FormattedDate(format, date):
                type = "formattedDate"
                attributes["format"] = format.map { String($0.rawValue) }
                attributes["date"] = String(date)
            case let .Custom(customType):
                type = "custom"
                attributes["type"] = String(customType)
            }
            return QwengramHistoryEntity(type: type, offset: Int32(clamping: entity.range.lowerBound), length: Int32(clamping: entity.range.count), attributes: attributes)
        }
    }.sorted { lhs, rhs in
        // Canonical order includes every content parameter and preserves duplicates.
        if lhs.offset != rhs.offset {
            return lhs.offset < rhs.offset
        }
        if lhs.length != rhs.length {
            return lhs.length < rhs.length
        }
        if lhs.type != rhs.type {
            return lhs.type < rhs.type
        }
        let lhsAttributes = lhs.attributes.sorted { $0.key < $1.key }.flatMap { [$0.key, $0.value] }
        let rhsAttributes = rhs.attributes.sorted { $0.key < $1.key }.flatMap { [$0.key, $0.value] }
        return lhsAttributes.lexicographicallyPrecedes(rhsAttributes)
    }
}
