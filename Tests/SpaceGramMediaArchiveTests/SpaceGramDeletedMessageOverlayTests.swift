import Foundation
import Postbox
import SpaceGramHistoryOverlay
import SpaceGramHistoryStorage
import SpaceGramMediaArchive
import TelegramCore
import XCTest

final class SpaceGramDeletedMessageOverlayTests: XCTestCase {
    private let peerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(42))

    func testCompletedResourcesSurviveUnlinkAndReconstructEveryMediaKind() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = SpaceGramMediaArchive.root(mediaBoxPath: directory.appendingPathComponent("media").path)
        let kinds = ["photo", "video", "voice", "videoMessage", "animation", "file", "sticker"]
        var captures: [SpaceGramMediaCapture] = []
        for kind in kinds {
            let source = directory.appendingPathComponent(kind)
            try Data(("received-" + kind).utf8).write(to: source)
            // Cache hits can complete on the main queue. Pin before an unlink.
            let capture = try XCTUnwrap(SpaceGramMediaArchive.pinCompletedFile(path: source.path, fileName: kind, kind: kind, fileExtension: "bin"))
            capture.resourceId = "fixture-" + kind
            captures.append(capture)
            try FileManager.default.removeItem(at: source)
        }
        let stored = expectation(description: "atomic archive publication")
        SpaceGramMediaArchive.store(root: root, captures: captures) { assets in
            XCTAssertEqual(assets.count, kinds.count)
            stored.fulfill()
        }
        wait(for: [stored], timeout: 10)
        let resolved = expectation(description: "resolve by stable resource identity without event asset IDs")
        var resources: [String: SpaceGramArchivedMedia] = [:]
        SpaceGramMediaArchive.resolve(root: root, ids: [], resourceIds: Set(kinds.map { "fixture-" + $0 })) {
            resources = $0
            resolved.fulfill()
        }
        wait(for: [resolved], timeout: 10)
        XCTAssertEqual(resources.count, kinds.count)
        for (index, kind) in kinds.enumerated() {
            let resource = try XCTUnwrap(resources.values.first { $0.asset.resourceId == "fixture-" + kind })
            XCTAssertEqual(try Data(contentsOf: resource.url), Data(("received-" + kind).utf8))
            var metadata = SpaceGramHistoryMediaMetadata(type: kind == "photo" ? "image" : "file")
            metadata.width = 320
            metadata.height = 240
            metadata.duration = 3
            metadata.isAnimated = kind == "animation"
            metadata.stickerText = kind == "sticker" ? "hello" : nil
            var snapshot = SpaceGramHistorySnapshot(text: "caption", originalMessageTimestamp: 150)
            snapshot.media = [metadata]
            snapshot.groupingKey = 123
            var item = SpaceGramDeletedMessageOverlayItem(originalMessageId: MessageId(peerId: self.peerId, namespace: Namespaces.Message.Cloud, id: Int32(index + 1)), threadId: nil, snapshot: snapshot, author: nil, chatPeer: nil, hasArchivedMedia: true, stableVersion: 1)
            item.archivedMedia = [resource]
            let message = item.makeMessage(accountPeerId: self.peerId, deletedLabel: "Deleted", archivedMediaLabel: "Archived", missingMediaLabel: "Media unavailable")
            XCTAssertEqual(message.text, "caption")
            XCTAssertEqual(message.groupingKey, 123)
            XCTAssertEqual(message.id.namespace, Namespaces.Message.Local)
            if kind == "photo" {
                XCTAssertNotNil(message.media.first as? TelegramMediaImage)
            } else {
                let file = try XCTUnwrap(message.media.first as? TelegramMediaFile)
                XCTAssertFalse(file.fileName?.contains("Media unavailable") == true)
                XCTAssertEqual(file.isVoice, kind == "voice")
                XCTAssertEqual(file.isInstantVideo, kind == "videoMessage")
                XCTAssertEqual(file.isSticker, kind == "sticker")
                XCTAssertEqual(file.isAnimated, kind == "animation")
            }
        }
    }

    func testChronologicalPageBoundaryPolicy() {
        XCTAssertFalse(SpaceGramDeletedOverlayPolicy.includes(timestamp: 90, lowerTimestamp: 100, upperTimestamp: 200, canExtendEarlier: false, canExtendLater: false))
        XCTAssertTrue(SpaceGramDeletedOverlayPolicy.includes(timestamp: 100, lowerTimestamp: 100, upperTimestamp: 200, canExtendEarlier: false, canExtendLater: false))
        XCTAssertTrue(SpaceGramDeletedOverlayPolicy.includes(timestamp: 150, lowerTimestamp: 100, upperTimestamp: 200, canExtendEarlier: false, canExtendLater: false))
        XCTAssertFalse(SpaceGramDeletedOverlayPolicy.includes(timestamp: 210, lowerTimestamp: 100, upperTimestamp: 200, canExtendEarlier: false, canExtendLater: false))
        XCTAssertTrue(SpaceGramDeletedOverlayPolicy.includes(timestamp: 90, lowerTimestamp: 100, upperTimestamp: 200, canExtendEarlier: true, canExtendLater: false))
        XCTAssertTrue(SpaceGramDeletedOverlayPolicy.includes(timestamp: 210, lowerTimestamp: 100, upperTimestamp: 200, canExtendEarlier: false, canExtendLater: true))
    }

    func testPresentationMessageIsLocalAndCarriesOriginalIdentity() {
        var snapshot = SpaceGramHistorySnapshot(text: "hello", originalMessageTimestamp: 150)
        snapshot.entities = [SpaceGramHistoryEntity(type: "bold", offset: 0, length: 5)]
        let originalId = MessageId(peerId: self.peerId, namespace: Namespaces.Message.Cloud, id: 7)
        let item = SpaceGramDeletedMessageOverlayItem(originalMessageId: originalId, threadId: nil, snapshot: snapshot, author: nil, chatPeer: nil, hasArchivedMedia: false, stableVersion: 1)
        let message = item.makeMessage(accountPeerId: self.peerId, deletedLabel: "Deleted", archivedMediaLabel: "Archived media", missingMediaLabel: "Media unavailable")

        XCTAssertEqual(message.id.namespace, Namespaces.Message.Local)
        XCTAssertEqual(message.timestamp, 150)
        XCTAssertEqual(message.text, "hello", "Presentation metadata must not alter copied text")
        XCTAssertEqual((message.attributes.first { $0 is TextEntitiesMessageAttribute } as? TextEntitiesMessageAttribute)?.entities.first?.range, 0 ..< 5)
        XCTAssertEqual((message.attributes.first { $0 is SpaceGramDeletedMessageAttribute } as? SpaceGramDeletedMessageAttribute)?.originalMessageId, originalId)
    }

    func testMissingMediaUsesGracefulPlaceholder() {
        var snapshot = SpaceGramHistorySnapshot(text: "", originalMessageTimestamp: 150)
        snapshot.media = [SpaceGramHistoryMediaMetadata(type: "image")]
        let item = SpaceGramDeletedMessageOverlayItem(
            originalMessageId: MessageId(peerId: self.peerId, namespace: Namespaces.Message.Cloud, id: 8),
            threadId: nil,
            snapshot: snapshot,
            author: nil,
            chatPeer: nil,
            hasArchivedMedia: false,
            stableVersion: 1
        )
        let message = item.makeMessage(accountPeerId: self.peerId, deletedLabel: "Deleted", archivedMediaLabel: "Archived media", missingMediaLabel: "Media unavailable")
        XCTAssertEqual(message.text, "")
        XCTAssertTrue((message.media.first as? TelegramMediaFile)?.fileName?.contains("Media unavailable") == true)
    }
}
