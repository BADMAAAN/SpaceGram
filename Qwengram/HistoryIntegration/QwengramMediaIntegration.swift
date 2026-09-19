import Foundation
import Postbox
import QwengramHistoryStorage
import QwengramMediaArchive
import QwengramSettings
import SwiftSignalKit

func qwengramPinMessageMedia(postbox: Postbox, message: Message) -> [QwengramMediaCapture] {
    guard QwengramSettings.shared.captureMedia,
          message.id.namespace == Namespaces.Message.Cloud,
          message.id.peerId.namespace != Namespaces.Peer.SecretChat else { return [] }
    var result: [QwengramMediaCapture] = []
    var seen = Set<MediaResourceId>()
    func pin(_ resource: MediaResource, name: String, kind: String, ext: String) {
        guard result.count < 32, seen.insert(resource.id).inserted else { return }
        // resourcePath is the complete-file path, never the partial download path.
        if let capture = QwengramMediaArchive.pinCompletedFile(path: postbox.mediaBox.resourcePath(resource), fileName: name, kind: kind, fileExtension: ext) {
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

func qwengramStoreMessageMedia(postbox: Postbox, key: QwengramHistoryMessageKey, captureId: String, captures: [QwengramMediaCapture]) {
    let root = QwengramMediaArchive.root(mediaBoxPath: postbox.mediaBox.basePath)
    QwengramMediaArchive.store(root: root, captures: captures) { assets in
        let ids = assets.map { $0.id }
        let _ = postbox.transaction { transaction -> Void in
            do {
                // Never recreate an archive record removed while copying, nor
                // attach an old job to a new incarnation of the same message.
                guard QwengramSettings.shared.captureMedia,
                      var record = try QwengramHistoryStore.load(transaction: transaction, key: key),
                      let index = record.events.firstIndex(where: { $0.mediaCaptureId == captureId }) else {
                    QwengramMediaArchive.remove(root: root, ids: ids)
                    return
                }
                record.events[index].mediaAssetIds = ids
                try QwengramHistoryStore.upsert(transaction: transaction, record: record)
                let references = QwengramHistoryStore.assetReferences(transaction: transaction)
                QwengramMediaArchive.reconcile(root: root, referencedIds: references.ids, referencesComplete: references.complete)
            } catch {
                QwengramMediaArchive.remove(root: root, ids: ids)
                NSLog("QwengramMediaArchive: history link failed")
            }
        }.start()
    }
}

// Used before local expiration, remote tombstoning, and initial timed-media
// consumption. A capture event describes saved content, not a claimed deletion.
func qwengramBeforeMediaExpiration(postbox: Postbox, transaction: Transaction, message: Message, source: String) {
    let captures = qwengramPinMessageMedia(postbox: postbox, message: message)
    guard !captures.isEmpty else { return }
    let key = QwengramHistoryMessageKey(peerId: message.id.peerId.toInt64(), namespace: message.id.namespace, id: message.id.id)
    do {
        var record = try QwengramHistoryStore.load(transaction: transaction, key: key) ?? QwengramHistoryRecord(key: key, threadId: message.threadId)
        guard record.nextRevision < Int64.max else { throw QwengramHistoryStorageError.invalidRevisionSequence }
        let timestamp = Int64(Date().timeIntervalSince1970)
        let captureId = UUID().uuidString
        let number = record.nextRevision
        record.nextRevision += 1
        record.revisions.append(QwengramHistoryRevision(number: number, observedTimestamp: timestamp, snapshot: qwengramHistorySnapshot(message)))
        var event = QwengramHistoryEvent(type: .cleanup, source: source, reason: .mediaArchive, observedTimestamp: timestamp, revisionNumber: number)
        event.mediaCaptureId = captureId
        record.events.append(event)
        try QwengramHistoryStore.upsert(transaction: transaction, record: record)
        qwengramStoreMessageMedia(postbox: postbox, key: key, captureId: captureId, captures: captures)
    } catch {
        NSLog("QwengramMediaArchive: capture event failed; Telegram continues")
    }
}
