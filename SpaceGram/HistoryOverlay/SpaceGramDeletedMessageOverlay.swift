import Foundation
import Postbox
import SpaceGramHistoryStorage
import SpaceGramMediaArchive
import SwiftSignalKit
import TelegramCore

public final class SpaceGramDeletedMessageAttribute: MessageAttribute {
    public let originalMessageId: MessageId
    private let mediaLeases: [SpaceGramArchivedMedia]

    public init(originalMessageId: MessageId, mediaLeases: [SpaceGramArchivedMedia] = []) {
        self.originalMessageId = originalMessageId
        self.mediaLeases = mediaLeases
    }

    public required init(decoder: PostboxDecoder) {
        self.mediaLeases = []
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
    public var assetIds: [String] = []
    public var archivedMedia: [SpaceGramArchivedMedia] = []
    public var nativeMedia: [Media] = []

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
        let text = self.snapshot.text
        let entities = self.snapshot.entities.compactMap { spaceGramMessageEntity($0, textLength: text.utf16.count) }

        let localId = Int32(bitPattern: UInt32(bitPattern: self.originalMessageId.id) ^ 0x80000000)
        let localMessageId = MessageId(peerId: self.originalMessageId.peerId, namespace: Namespaces.Message.Local, id: localId)
        var peers = SimpleDictionary<PeerId, Peer>()
        if let chatPeer = self.chatPeer {
            peers[chatPeer.id] = chatPeer
        }
        if let author = self.author {
            peers[author.id] = author
        }
        let incoming = self.snapshot.authorPeerId != accountPeerId.toInt64()
        var attributes: [MessageAttribute] = [
            TextEntitiesMessageAttribute(entities: entities),
            SpaceGramDeletedMessageAttribute(originalMessageId: self.originalMessageId, mediaLeases: self.archivedMedia)
        ]
        if self.snapshot.hasMediaSpoiler == true { attributes.append(MediaSpoilerMessageAttribute()) }
        if let edited = self.snapshot.serverEditTimestamp {
            attributes.append(EditedMessageAttribute(date: Int32(clamping: edited), isHidden: false))
        }
        return Message(
            stableId: UInt32(bitPattern: localId),
            stableVersion: self.stableVersion,
            id: localMessageId,
            globallyUniqueId: nil,
            groupingKey: self.snapshot.groupingKey,
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
            attributes: attributes,
            media: self.makeMedia(missingMediaLabel: missingMediaLabel),
            peers: peers,
            associatedMessages: SimpleDictionary<MessageId, Message>(),
            associatedMessageIds: [],
            associatedMedia: [:],
            associatedThreadInfo: nil,
            associatedStories: [:]
        )
    }

    private func makeMedia(missingMediaLabel: String) -> [Media] {
        return self.snapshot.media.flatMap { self.makeMedia(metadata: $0, missingMediaLabel: missingMediaLabel) }
    }

    private func makeMedia(metadata: SpaceGramHistoryMediaMetadata, missingMediaLabel: String) -> [Media] {
        let resourceIds = Set(metadata.resourceIds ?? [])
        let mediaAssets = self.archivedMedia.filter {
            resourceIds.isEmpty || $0.asset.resourceId.map(resourceIds.contains) == true
                || ($0.asset.resourceId == nil && self.snapshot.media.count == 1)
        }
        let primary = mediaAssets.filter { metadata.type == "image" || $0.asset.kind != "thumbnail" }.max { $0.asset.bytes < $1.asset.bytes }
        let assetNumber = primary.flatMap { UInt64($0.asset.id.replacingOccurrences(of: "-", with: "").prefix(16), radix: 16) }
        let localNumber = assetNumber.map { Int64(bitPattern: $0) } ?? (self.originalMessageId.peerId.toInt64() ^ (Int64(self.originalMessageId.id) << 32))
        let mediaId = MediaId(namespace: Namespaces.Media.LocalFile, id: localNumber)
        let native = self.nativeMedia.first { media in
            if let image = media as? TelegramMediaImage {
                return metadata.type == "image" && metadata.identifiers["namespace"] == String(image.imageId.namespace) && metadata.identifiers["id"] == String(image.imageId.id)
            } else if let file = media as? TelegramMediaFile {
                return metadata.type == "file" && metadata.identifiers["namespace"] == String(file.fileId.namespace) && metadata.identifiers["id"] == String(file.fileId.id)
            }
            return false
        }
        guard let primary else {
            // A verified complete MediaBox resource is preferable while the
            // private archive publication is still in flight.
            if let native {
                return [native]
            }
            // An explicit unavailable resource keeps the caption intact without
            // inventing an empty local path or claiming a thumbnail is full media.
            return [TelegramMediaFile(fileId: mediaId, partialReference: nil,
                resource: EmptyMediaResource(),
                previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: nil,
                mimeType: "application/octet-stream", size: metadata.size,
                attributes: [.FileName(fileName: (metadata.filename ?? metadata.type) + " — " + missingMediaLabel)], alternativeRepresentations: [])]
        }
        func resource(_ value: SpaceGramArchivedMedia) -> LocalFileReferenceMediaResource {
            let hex = value.asset.id.replacingOccurrences(of: "-", with: "")
            let id = Int64(bitPattern: UInt64(hex.prefix(16), radix: 16) ?? 0)
            return LocalFileReferenceMediaResource(localFilePath: value.url.path, randomId: id, size: value.asset.bytes)
        }
        if let image = native as? TelegramMediaImage, primary.asset.kind == "photo" {
            let dimensions = image.representations.max(by: {
                Int64($0.dimensions.width) * Int64($0.dimensions.height) < Int64($1.dimensions.width) * Int64($1.dimensions.height)
            })?.dimensions ?? PixelDimensions(width: 512, height: 512)
            return [TelegramMediaImage(imageId: image.imageId,
                representations: [TelegramMediaImageRepresentation(dimensions: dimensions, resource: resource(primary), progressiveSizes: [], immediateThumbnailData: image.immediateThumbnailData, hasVideo: false, isPersonal: false)],
                videoRepresentations: [], immediateThumbnailData: image.immediateThumbnailData, emojiMarkup: image.emojiMarkup,
                reference: image.reference, partialReference: image.partialReference, flags: image.flags, video: nil)]
        } else if let file = native as? TelegramMediaFile, primary.asset.kind != "thumbnail" {
            let previews = mediaAssets.filter { $0.asset.kind == "thumbnail" }.prefix(1).map {
                TelegramMediaImageRepresentation(dimensions: file.dimensions ?? PixelDimensions(width: 512, height: 512), resource: resource($0), progressiveSizes: [], immediateThumbnailData: nil, hasVideo: false, isPersonal: false)
            }
            return [TelegramMediaFile(fileId: file.fileId, partialReference: file.partialReference, resource: resource(primary),
                previewRepresentations: previews, videoThumbnails: [], videoCover: file.videoCover,
                immediateThumbnailData: file.immediateThumbnailData, mimeType: file.mimeType, size: primary.asset.bytes,
                attributes: file.attributes, alternativeRepresentations: [])]
        }
        let dimensions = PixelDimensions(width: max(1, min(16384, metadata.width ?? 512)), height: max(1, min(16384, metadata.height ?? 512)))
        if primary.asset.kind == "photo" || metadata.type == "image" {
            return [TelegramMediaImage(imageId: mediaId,
                representations: [TelegramMediaImageRepresentation(dimensions: dimensions, resource: resource(primary), progressiveSizes: [], immediateThumbnailData: nil, hasVideo: false, isPersonal: false)],
                immediateThumbnailData: nil, reference: nil, partialReference: nil, flags: [])]
        }
        var fileAttributes: [TelegramMediaFileAttribute] = [.FileName(fileName: primary.asset.fileName)]
        if primary.asset.kind == "sticker" || metadata.stickerText != nil {
            fileAttributes.append(.Sticker(displayText: metadata.stickerText ?? "", packReference: nil, maskData: nil))
            fileAttributes.append(.ImageSize(size: dimensions))
        }
        let rawDuration = metadata.duration ?? 0
        let duration = rawDuration.isFinite ? max(0, min(rawDuration, Double(Int32.max))) : 0
        if primary.asset.kind == "voice" || metadata.isVoice == true {
            fileAttributes.append(.Audio(isVoice: true, duration: Int(duration), title: nil, performer: nil, waveform: nil))
        } else if primary.asset.kind == "video" || primary.asset.kind == "videoMessage" || metadata.isInstantVideo == true || (primary.asset.kind == "animation" && metadata.mimeType == "video/mp4") {
            fileAttributes.append(.Video(duration: duration, size: dimensions, flags: primary.asset.kind == "videoMessage" || metadata.isInstantVideo == true ? [.instantRoundVideo] : [], preloadSize: nil, coverTime: nil, videoCodec: nil))
        }
        if primary.asset.kind == "animation" || metadata.isAnimated == true { fileAttributes.append(.Animated) }
        let previews = mediaAssets.filter { $0.asset.kind == "thumbnail" }.prefix(1).map {
            TelegramMediaImageRepresentation(dimensions: dimensions, resource: resource($0), progressiveSizes: [], immediateThumbnailData: nil, hasVideo: false, isPersonal: false)
        }
        let mime = metadata.isInstantVideo == true ? "video/mp4" : (metadata.mimeType ?? (primary.asset.fileExtension == "mp4" ? "video/mp4" : (primary.asset.kind == "voice" ? "audio/ogg" : "application/octet-stream")))
        return [TelegramMediaFile(fileId: mediaId, partialReference: nil, resource: resource(primary), previewRepresentations: previews,
            videoThumbnails: [], immediateThumbnailData: nil, mimeType: mime, size: primary.asset.bytes, attributes: fileAttributes, alternativeRepresentations: [])]
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
                var item = SpaceGramDeletedMessageOverlayItem(
                    originalMessageId: originalMessageId,
                    threadId: record.threadId,
                    snapshot: snapshot,
                    author: author,
                    chatPeer: chatPeer,
                    hasArchivedMedia: !(deleteEvent.mediaAssetIds ?? []).isEmpty,
                    stableVersion: UInt32(truncatingIfNeeded: record.nextRevision) &+ UInt32(record.events.reduce(0) { $0 + ($1.mediaAssetIds?.count ?? 0) })
                )
                // A completed-download capture can predate deletion. Only reuse
                // captures of the same attachment identity, never a previous edit.
                item.assetIds = record.events.reversed().filter { event in
                    guard !(event.mediaAssetIds ?? []).isEmpty,
                          let revision = record.revisions.first(where: { $0.number == event.revisionNumber }) else { return false }
                    return revision.snapshot.media.map(\.identifiers) == snapshot.media.map(\.identifiers)
                }.flatMap { $0.mediaAssetIds ?? [] }
                return item
            }.sorted { lhs, rhs in
                if lhs.timestamp != rhs.timestamp {
                    return lhs.timestamp < rhs.timestamp
                }
                return lhs.originalMessageId.id < rhs.originalMessageId.id
            }
        }
    }
    |> mapToSignal { items in
        return Signal { subscriber in
            let resourceIds = Set(items.flatMap { $0.snapshot.media.flatMap { $0.resourceIds ?? [] } })
            SpaceGramMediaArchive.resolve(root: SpaceGramMediaArchive.root(mediaBoxPath: postbox.mediaBox.basePath), ids: Set(items.flatMap(\.assetIds)), resourceIds: resourceIds) { resources in
                subscriber.putNext(items.map { item in
                    var item = item
                    let matchingIds = Set(item.snapshot.media.flatMap { $0.resourceIds ?? [] })
                    item.archivedMedia = resources.values.filter { item.assetIds.contains($0.asset.id) || $0.asset.resourceId.map(matchingIds.contains) == true }
                    item.nativeMedia = item.snapshot.media.compactMap { metadata in
                        guard let data = metadata.nativeMediaPayload,
                              let media = PostboxDecoder(buffer: MemoryBuffer(data: data)).decodeRootObject() as? Media else { return nil }
                        if !item.archivedMedia.isEmpty {
                            return media
                        } else if let image = media as? TelegramMediaImage,
                                  let largest = image.representations.max(by: {
                                      Int64($0.dimensions.width) * Int64($0.dimensions.height) < Int64($1.dimensions.width) * Int64($1.dimensions.height)
                                  }), postbox.mediaBox.completedResourcePath(largest.resource) != nil {
                            return image
                        } else if let file = media as? TelegramMediaFile,
                                  postbox.mediaBox.completedResourcePath(file.resource) != nil {
                            return file
                        } else {
                            return nil
                        }
                    }
                    return item
                })
                subscriber.putCompletion()
            }
            return EmptyDisposable
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
