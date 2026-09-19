import Foundation
import Postbox
import SpaceGramHistoryStorage
import SpaceGramMediaArchive
import SpaceGramSettings
import SwiftSignalKit

func spaceGramPinMessageMedia(postbox: Postbox, message: Message) -> [SpaceGramMediaCapture] {
    guard SpaceGramSettings.shared.captureMedia,
          message.id.namespace == Namespaces.Message.Cloud,
          message.id.peerId.namespace != Namespaces.Peer.SecretChat else { return [] }
    var result: [SpaceGramMediaCapture] = []
    var seen = Set<MediaResourceId>()
    func pin(_ resource: MediaResource, name: String, kind: String, ext: String) {
        guard result.count < 32, seen.insert(resource.id).inserted else { return }
        // resourcePath is the complete-file path, never the partial download path.
        if let capture = SpaceGramMediaArchive.pinCompletedFile(path: postbox.mediaBox.resourcePath(resource), fileName: name, kind: kind, fileExtension: ext) {
            result.append(capture)
        }
    }
    for media in message.effectiveMedia {
        if let image = media as? TelegramMediaImage {
            // Largest first so a bounded batch favors the original over thumbnails.
            let representations = image.representations.sorted {
                Int64($0.dimensions.width) * Int64($0.dimensions.height) > Int64($1.dimensions.width) * Int64($1.dimensions.height)
            }
            for (index, representation) in representations.enumerated() {
                pin(representation.resource, name: index == 0 ? "photo.jpg" : "thumbnail.jpg", kind: index == 0 ? "photo" : "thumbnail", ext: "jpg")
            }
        } else if let file = media as? TelegramMediaFile {
            let kind = file.isInstantVideo ? "videoMessage" : (file.isVoice ? "voice" : (file.isAnimated ? "animation" : (file.isVideo ? "video" : "file")))
            let fallbackExtension: String
            switch file.mimeType {
            case "video/mp4": fallbackExtension = "mp4"
            case "audio/ogg": fallbackExtension = "ogg"
            case "audio/mpeg": fallbackExtension = "mp3"
            case "image/gif": fallbackExtension = "gif"
            case "image/jpeg": fallbackExtension = "jpg"
            case "image/png": fallbackExtension = "png"
            case "application/pdf": fallbackExtension = "pdf"
            default: fallbackExtension = "bin"
            }
            let name = file.fileName ?? (kind + "." + fallbackExtension)
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
                    SpaceGramMediaArchive.remove(root: root, ids: ids)
                    return
                }
                record.events[index].mediaAssetIds = ids
                try SpaceGramHistoryStore.upsert(transaction: transaction, record: record)
                let references = SpaceGramHistoryStore.assetReferences(transaction: transaction)
                SpaceGramMediaArchive.reconcile(root: root, referencedIds: references.ids, referencesComplete: references.complete)
            } catch {
                SpaceGramMediaArchive.remove(root: root, ids: ids)
                NSLog("SpaceGramMediaArchive: history link failed")
            }
        }.start()
    }
}

// Used before local expiration, remote tombstoning, and initial timed-media
// consumption. A capture event describes saved content, not a claimed deletion.
func spaceGramBeforeMediaExpiration(postbox: Postbox, transaction: Transaction, message: Message, source: String) {
    let captures = spaceGramPinMessageMedia(postbox: postbox, message: message)
    guard !captures.isEmpty else { return }
    let key = SpaceGramHistoryMessageKey(peerId: message.id.peerId.toInt64(), namespace: message.id.namespace, id: message.id.id)
    do {
        var record = try SpaceGramHistoryStore.load(transaction: transaction, key: key) ?? SpaceGramHistoryRecord(key: key, threadId: message.threadId)
        guard record.nextRevision < Int64.max else { throw SpaceGramHistoryStorageError.invalidRevisionSequence }
        let timestamp = Int64(Date().timeIntervalSince1970)
        let captureId = UUID().uuidString
        let number = record.nextRevision
        record.nextRevision += 1
        record.revisions.append(SpaceGramHistoryRevision(number: number, observedTimestamp: timestamp, snapshot: spaceGramHistorySnapshot(message)))
        var event = SpaceGramHistoryEvent(type: .cleanup, source: source, reason: .mediaArchive, observedTimestamp: timestamp, revisionNumber: number)
        event.mediaCaptureId = captureId
        record.events.append(event)
        try SpaceGramHistoryStore.upsert(transaction: transaction, record: record)
        spaceGramStoreMessageMedia(postbox: postbox, key: key, captureId: captureId, captures: captures)
    } catch {
        NSLog("SpaceGramMediaArchive: capture event failed; Telegram continues")
    }
}
