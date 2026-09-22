import Foundation
import Postbox
import SpaceGramHistoryStorage
import SpaceGramMediaArchive
import SpaceGramSettings
import SpaceGramSettingsSignal
import SwiftSignalKit

func spaceGramPinMessageMedia(postbox: Postbox, message: Message) -> [SpaceGramMediaCapture] {
    guard SpaceGramSettings.shared.captureMedia,
          message.id.namespace == Namespaces.Message.Cloud,
          message.id.peerId.namespace != Namespaces.Peer.SecretChat else { return [] }
    return spaceGramPinMedia(mediaBox: postbox.mediaBox, media: message.effectiveMedia)
}

private func spaceGramPinMedia(mediaBox: MediaBox, media: [Media]) -> [SpaceGramMediaCapture] {
    var result: [SpaceGramMediaCapture] = []
    var seen = Set<MediaResourceId>()
    func pin(_ resource: MediaResource, name: String, kind: String, ext: String) {
        guard result.count < 32, seen.insert(resource.id).inserted else { return }
        // resourcePath is the complete-file path, never the partial download path.
        if let capture = SpaceGramMediaArchive.pinCompletedFile(path: mediaBox.resourcePath(resource), fileName: name, kind: kind, fileExtension: ext) {
            capture.resourceId = resource.id.stringRepresentation
            result.append(capture)
        }
    }
    for media in media {
        if let image = media as? TelegramMediaImage {
            // Largest first so a bounded batch favors the original over thumbnails.
            let representations = image.representations.sorted {
                Int64($0.dimensions.width) * Int64($0.dimensions.height) > Int64($1.dimensions.width) * Int64($1.dimensions.height)
            }
            for representation in representations {
                let isPhoto = max(representation.dimensions.width, representation.dimensions.height) > 100
                pin(representation.resource, name: isPhoto ? "photo.jpg" : "thumbnail.jpg", kind: isPhoto ? "photo" : "thumbnail", ext: "jpg")
            }
        } else if let file = media as? TelegramMediaFile {
            let kind = file.isSticker ? "sticker" : (file.isInstantVideo ? "videoMessage" : (file.isVoice ? "voice" : (file.isAnimated ? "animation" : (file.isVideo ? "video" : "file"))))
            let fallbackExtension: String
            switch file.mimeType {
            case "video/mp4": fallbackExtension = "mp4"
            case "audio/ogg": fallbackExtension = "ogg"
            case "audio/mpeg": fallbackExtension = "mp3"
            case "image/gif": fallbackExtension = "gif"
            case "image/jpeg": fallbackExtension = "jpg"
            case "image/png": fallbackExtension = "png"
            case "image/webp": fallbackExtension = "webp"
            case "application/x-tgsticker": fallbackExtension = "tgs"
            case "video/webm": fallbackExtension = "webm"
            case "application/pdf": fallbackExtension = "pdf"
            default: fallbackExtension = "bin"
            }
            let name = file.isInstantVideo ? "video.mp4" : (file.fileName ?? (kind + "." + fallbackExtension))
            let ext = (name as NSString).pathExtension
            pin(file.resource, name: name, kind: kind, ext: ext.isEmpty ? fallbackExtension : ext)
            for preview in file.previewRepresentations {
                pin(preview.resource, name: "thumbnail.jpg", kind: "thumbnail", ext: "jpg")
            }
        }
    }
    return result
}

func spaceGramStoreMessageMedia(postbox: Postbox, key: SpaceGramHistoryMessageKey, captureId: String, captures: [SpaceGramMediaCapture]) {
    let root = SpaceGramMediaArchive.root(mediaBoxPath: postbox.mediaBox.basePath)
    SpaceGramMediaArchive.store(root: root, captures: captures) { assets in
        let ids = assets.map { $0.id }
        let _ = postbox.transaction { transaction -> Void in
            do {
                // Never recreate an archive record removed while copying, nor
                // attach an old job to a new incarnation of the same message.
                guard SpaceGramSettings.shared.captureMedia,
                      var record = try SpaceGramHistoryStore.load(transaction: transaction, key: key),
                      let index = record.events.firstIndex(where: { $0.mediaCaptureId == captureId }) else {
                    // Resource-indexed assets may be shared by another message.
                    // Retention/capacity cleanup owns their lifetime.
                    return
                }
                record.events[index].mediaAssetIds = ids
                if assets.count != captures.count {
                    // An incomplete capture must be retryable on the next native completion.
                    record.events[index].mediaCaptureId = nil
                    record.events[index].mediaResourceIds = nil
                }
                try SpaceGramHistoryStore.upsert(transaction: transaction, record: record)
                let references = SpaceGramHistoryStore.assetReferences(transaction: transaction)
                SpaceGramMediaArchive.reconcile(root: root, referencedIds: references.ids, referencesComplete: references.complete)
            } catch {
                NSLog("SpaceGramMediaArchive: history link failed")
            }
        }.start()
    }
}

// Used before local expiration, remote tombstoning, and initial timed-media
// consumption. A capture event describes saved content, not a claimed deletion.
func spaceGramBeforeMediaExpiration(postbox: Postbox, transaction: Transaction, message: Message, source: String, completedCaptures: [SpaceGramMediaCapture]? = nil) {
    let captures = completedCaptures ?? spaceGramPinMessageMedia(postbox: postbox, message: message)
    spaceGramRecordMediaCapture(postbox: postbox, transaction: transaction, id: message.id, threadId: message.threadId, snapshot: spaceGramHistorySnapshot(message), source: source, captures: captures)
}

private func spaceGramRecordMediaCapture(postbox: Postbox, transaction: Transaction, id: MessageId, threadId: Int64?, snapshot: SpaceGramHistorySnapshot, source: String, captures: [SpaceGramMediaCapture]) {
    guard !captures.isEmpty else { return }
    let key = SpaceGramHistoryMessageKey(peerId: id.peerId.toInt64(), namespace: id.namespace, id: id.id)
    do {
        var record = try SpaceGramHistoryStore.load(transaction: transaction, key: key) ?? SpaceGramHistoryRecord(key: key, threadId: threadId)
        let resourceIds = captures.compactMap(\.resourceId)
        if source == "completedDownload", record.events.contains(where: {
            Set($0.mediaResourceIds ?? []).isSuperset(of: resourceIds) && $0.mediaCaptureId != nil
        }) { return }
        guard record.nextRevision < Int64.max else { throw SpaceGramHistoryStorageError.invalidRevisionSequence }
        let timestamp = Int64(Date().timeIntervalSince1970)
        let captureId = UUID().uuidString
        let number = record.nextRevision
        record.nextRevision += 1
        record.revisions.append(SpaceGramHistoryRevision(number: number, observedTimestamp: timestamp, snapshot: snapshot))
        var event = SpaceGramHistoryEvent(type: .cleanup, source: source, reason: .mediaArchive, observedTimestamp: timestamp, revisionNumber: number)
        event.mediaCaptureId = captureId
        event.mediaResourceIds = resourceIds
        record.events.append(event)
        try SpaceGramHistoryStore.upsert(transaction: transaction, record: record)
        spaceGramStoreMessageMedia(postbox: postbox, key: key, captureId: captureId, captures: captures)
    } catch {
        NSLog("SpaceGramMediaArchive: capture event failed; Telegram continues")
    }
}

// Observe local completion by resource id, regardless of which renderer/fetcher
// downloaded it. This subscribes to data availability and never starts a fetch.
// The bounded received-snapshot collection also restores associations on launch.
func spaceGramObserveReceivedMedia(postbox: Postbox) -> Disposable {
    final class Observation {
        var targets: [SpaceGramReceivedMessageSnapshot] = []
        var disposable: Disposable?
    }
    let queue = Queue(name: "SpaceGram.ReceivedMedia")
    var observations: [String: Observation] = [:]
    let viewKey = PostboxViewKey.orderedItemList(id: SpaceGramMessageSnapshotStore.collectionId)
    let snapshots = combineLatest(postbox.combinedView(keys: [viewKey]), spaceGramSettingsChangesSignal())
    |> mapToSignal { _ -> Signal<[SpaceGramReceivedMessageSnapshot], NoError> in
        return postbox.transaction { transaction in
            SpaceGramSettings.shared.captureMedia ? SpaceGramMessageSnapshotStore.list(transaction: transaction) : []
        }
    }
    |> deliverOn(queue)
    let subscription = snapshots.start(next: { snapshots in
        let targetsByResourceId = SpaceGramMessageSnapshotStore.targetsByResourceId(snapshots)
        for received in snapshots {
            for metadata in received.snapshot.media {
                for (index, resourceId) in (metadata.resourceIds ?? []).prefix(32).enumerated() {
                    if let observation = observations[resourceId] {
                        observation.targets = targetsByResourceId[resourceId] ?? []
                        continue
                    }
                    let isThumbnail = index != 0
                    let kind = isThumbnail ? "thumbnail" : (metadata.type == "image" ? "photo" : (metadata.isInstantVideo == true ? "videoMessage" : (metadata.isVoice == true ? "voice" : (metadata.isAnimated == true ? "animation" : (metadata.mimeType?.hasPrefix("video/") == true ? "video" : "file")))))
                    let ext: String
                    if isThumbnail || metadata.type == "image" { ext = "jpg" }
                    else if metadata.isInstantVideo == true { ext = "mp4" }
                    else if metadata.isVoice == true { ext = "ogg" }
                    else {
                        switch metadata.mimeType {
                        case "video/mp4": ext = "mp4"
                        case "audio/mpeg": ext = "mp3"
                        case "audio/ogg": ext = "ogg"
                        case "image/gif": ext = "gif"
                        case "image/webp": ext = "webp"
                        case "video/webm": ext = "webm"
                        default: ext = metadata.filename.map { ($0 as NSString).pathExtension } ?? "bin"
                        }
                    }
                    let name = isThumbnail ? "thumbnail.jpg" : (metadata.filename ?? (kind + "." + ext))
                    let observation = Observation()
                    observation.targets = targetsByResourceId[resourceId] ?? []
                    observations[resourceId] = observation
                    observation.disposable = (postbox.mediaBox.resourceData(id: MediaResourceId(resourceId))
                    |> filter { $0.complete && $0.size > 0 }
                    |> take(1)).start(next: { [weak postbox, weak observation] data in
                        guard let postbox, let observation, SpaceGramSettings.shared.captureMedia else { return }
                        // Pin one descriptor per message before hopping queues. A
                        // shared Telegram resource may belong to multiple snapshots,
                        // and a delete may unlink MediaBox while the transaction waits.
                        let targets = observation.targets.prefix(32).compactMap { received -> (SpaceGramReceivedMessageSnapshot, SpaceGramMediaCapture)? in
                            guard let capture = SpaceGramMediaArchive.pinCompletedFile(path: data.path, fileName: name, kind: kind, fileExtension: ext) else { return nil }
                            capture.resourceId = resourceId
                            return (received, capture)
                        }
                        guard !targets.isEmpty else { return }
                        let _ = postbox.transaction { transaction -> Void in
                            guard SpaceGramSettings.shared.captureMedia else { return }
                            for (received, capture) in targets {
                                guard SpaceGramMessageSnapshotStore.load(transaction: transaction, key: received.key) != nil else { continue }
                                let id = MessageId(peerId: PeerId(received.key.peerId), namespace: received.key.namespace, id: received.key.id)
                                spaceGramRecordMediaCapture(postbox: postbox, transaction: transaction, id: id, threadId: received.threadId,
                                    snapshot: received.snapshot, source: "completedDownload", captures: [capture])
                            }
                        }.start()
                    })
                }
            }
        }
        for id in Array(observations.keys) where targetsByResourceId[id] == nil {
            observations.removeValue(forKey: id)?.disposable?.dispose()
        }
    })
    return ActionDisposable {
        subscription.dispose()
        queue.async {
            for observation in observations.values { observation.disposable?.dispose() }
            observations.removeAll()
        }
    }
}

// Account-lifetime observation of completed fetches, including other chats.
// Fetching remains native; this does not request or download additional bytes.
let spaceGramMediaDownloadCompleted = Notification.Name("SpaceGram.MediaDownloadCompleted")

func spaceGramMediaResourceCompleted(mediaBox: MediaBox, reference: MediaResourceReference) {
    guard SpaceGramSettings.shared.captureMedia, case let .media(mediaReference, _) = reference else { return }
    // Sticker/GIF renderers use pack/recent/standalone references, not message
    // references. Save their cloud bytes by resource identity before any deletion.
    switch mediaReference {
    case .stickerPack, .savedSticker, .recentSticker, .savedGif, .standalone:
        if let file = mediaReference.media as? TelegramMediaFile,
           file.resource is CloudDocumentMediaResource, file.isSticker || file.isAnimated {
            let captures = spaceGramPinMedia(mediaBox: mediaBox, media: [file])
            guard !captures.isEmpty else { return }
            SpaceGramMediaArchive.store(root: SpaceGramMediaArchive.root(mediaBoxPath: mediaBox.basePath), captures: captures) { _ in }
        }
        return
    default:
        break
    }
    guard case let .message(message, media) = mediaReference, let id = message.id,
          id.namespace == Namespaces.Message.Cloud,
          id.peerId.namespace != Namespaces.Peer.SecretChat else { return }
    // Pin the inode synchronously at completion, BEFORE the next Postbox
    // transaction can process a deletion/cache unlink. Copy/hash stays off-queue.
    let captures = spaceGramPinMedia(mediaBox: mediaBox, media: [media])
    guard !captures.isEmpty else { return }
    NotificationCenter.default.post(name: spaceGramMediaDownloadCompleted, object: mediaBox, userInfo: ["messageId": id, "captures": captures])
}

func spaceGramObserveMediaDownloads(postbox: Postbox) -> Disposable {
    let observer = NotificationCenter.default.addObserver(forName: spaceGramMediaDownloadCompleted, object: postbox.mediaBox, queue: nil) { [weak postbox] notification in
        guard let postbox, SpaceGramSettings.shared.captureMedia,
              let id = notification.userInfo?["messageId"] as? MessageId,
              let captures = notification.userInfo?["captures"] as? [SpaceGramMediaCapture] else { return }
        let _ = postbox.transaction { transaction -> Void in
            guard SpaceGramSettings.shared.captureMedia else { return }
            if let message = transaction.getMessage(id) {
                let resourceIds = Set(spaceGramHistorySnapshot(message).media.flatMap { $0.resourceIds ?? [] })
                let matching = captures.filter { $0.resourceId.map(resourceIds.contains) == true }
                spaceGramBeforeMediaExpiration(postbox: postbox, transaction: transaction, message: message, source: "completedDownload", completedCaptures: matching)
            } else {
                // A deletion can win the transaction race after the fd was
                // pinned. Attach to its existing snapshot; never recreate a row.
                let key = SpaceGramHistoryMessageKey(peerId: id.peerId.toInt64(), namespace: id.namespace, id: id.id)
                guard let record = try? SpaceGramHistoryStore.load(transaction: transaction, key: key),
                      let snapshot = SpaceGramHistoryPresentationModel.deletedSnapshot(record) else { return }
                let resourceIds = Set(snapshot.media.flatMap { $0.resourceIds ?? [] })
                let matching = captures.filter { $0.resourceId.map(resourceIds.contains) == true }
                spaceGramRecordMediaCapture(postbox: postbox, transaction: transaction, id: id, threadId: record.threadId, snapshot: snapshot, source: "completedDownload", captures: matching)
            }
        }.start()
    }
    return ActionDisposable { NotificationCenter.default.removeObserver(observer) }
}
