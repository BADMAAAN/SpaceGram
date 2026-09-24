import Foundation
import Postbox
import SpaceGramHistoryOverlay
import SpaceGramHistoryStorage
import SpaceGramMediaArchive
import TelegramCore
import XCTest

private final class SpaceGramOverlayTestCallbackValue<Value> {
    private let lock = NSLock()
    private var value: Value?

    func store(_ value: Value) {
        lock.lock()
        self.value = value
        lock.unlock()
    }

    func load() -> Value? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

final class SpaceGramDeletedMessageOverlayTests: XCTestCase {
    private let peerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(42))

    override class func setUp() {
        super.setUp()
        initializeAccountManagement()
    }

    private func waitForCallback<Value>(_ description: String, _ operation: (@escaping (Value) -> Void) -> Void) throws -> Value {
        let value = SpaceGramOverlayTestCallbackValue<Value>()
        let completed = DispatchSemaphore(value: 0)
        operation {
            value.store($0)
            completed.signal()
        }
        guard completed.wait(timeout: .now() + 10.0) == .success else {
            throw SpaceGramOverlayTestError.timedOut(description)
        }
        return try XCTUnwrap(value.load(), "Missing callback value for \(description)")
    }

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
        let assets = try waitForCallback("atomic archive publication") {
            SpaceGramMediaArchive.store(root: root, captures: captures, completion: $0)
        }
        XCTAssertEqual(assets.count, kinds.count)
        var resources = try waitForCallback("resolve by stable resource identity without event asset IDs") {
            SpaceGramMediaArchive.resolve(root: root, ids: [], resourceIds: Set(kinds.map { "fixture-" + $0 }), completion: $0)
        }
        XCTAssertEqual(resources.count, kinds.count)
        for (index, kind) in kinds.enumerated() {
            let resource = try XCTUnwrap(resources.values.first { $0.asset.resourceId == "fixture-" + kind })
            XCTAssertEqual(try Data(contentsOf: resource.url), Data(("received-" + kind).utf8))
            var metadata = SpaceGramHistoryMediaMetadata(type: kind == "photo" ? "image" : "file")
            metadata.resourceIds = ["fixture-" + kind]
            metadata.isInstantVideo = kind == "videoMessage"
            metadata.mimeType = kind == "videoMessage" ? "video/mp3" : nil
            metadata.width = 320
            metadata.height = 240
            metadata.duration = 3
            metadata.isAnimated = kind == "animation"
            metadata.stickerText = kind == "sticker" ? "hello" : nil
            var snapshot = SpaceGramHistorySnapshot(text: "caption", originalMessageTimestamp: 150)
            snapshot.media = [metadata]
            snapshot.groupingKey = 123
            var item = SpaceGramDeletedMessageOverlayItem(originalMessageId: MessageId(peerId: self.peerId, namespace: Namespaces.Message.Cloud, id: Int32(index + 1)), threadId: nil, snapshot: snapshot, author: nil, chatPeer: nil, hasArchivedMedia: true, stableVersion: 1)
            // Other album items must never supply this bubble's primary bytes.
            item.archivedMedia = Array(resources.values)
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
                if kind == "videoMessage" { XCTAssertEqual(file.mimeType, "video/mp4") }
                XCTAssertEqual(file.isSticker, kind == "sticker")
                XCTAssertEqual(file.isAnimated, kind == "animation")
            }
        }
        resources.removeAll()
        _ = try waitForCallback("archive queue drain") { SpaceGramMediaArchive.usage(root: root, completion: $0) }
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
        let unavailable = message.media.first as? TelegramMediaFile
        XCTAssertTrue(unavailable?.fileName?.contains("Media unavailable") == true)
        XCTAssertTrue(unavailable?.resource is EmptyMediaResource)
    }

    func testNativeRoundVideoDescriptorSurvivesHistoryEncodingAndAvoidsEmptyFallback() throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data([0, 1, 2, 3]).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }
        let fileId = MediaId(namespace: Namespaces.Media.CloudFile, id: 77)
        let resource = LocalFileReferenceMediaResource(localFilePath: source.path, randomId: 77, size: 4)
        let original = TelegramMediaFile(fileId: fileId, partialReference: nil, resource: resource,
            previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: nil, mimeType: "video/mp4", size: 4,
            attributes: [.FileName(fileName: "round.mp4"), .Video(duration: 2, size: PixelDimensions(width: 240, height: 240), flags: [.instantRoundVideo], preloadSize: nil, coverTime: nil, videoCodec: nil)],
            alternativeRepresentations: [])
        let encoder = PostboxEncoder()
        encoder.encodeRootObject(original)
        let originalPayload = encoder.makeData()
        XCTAssertFalse(originalPayload.isEmpty)
        var metadata = SpaceGramHistoryMediaMetadata(type: "file")
        metadata.identifiers = ["namespace": String(fileId.namespace), "id": String(fileId.id)]
        metadata.resourceIds = [resource.id.stringRepresentation]
        metadata.nativeMediaPayload = originalPayload
        var snapshot = SpaceGramHistorySnapshot(text: "", originalMessageTimestamp: 150)
        snapshot.media = [metadata]

        let directlyDecoded = try XCTUnwrap(PostboxDecoder(buffer: MemoryBuffer(data: originalPayload)).decodeRootObject() as? TelegramMediaFile)
        XCTAssertEqual(directlyDecoded.fileId, fileId)
        XCTAssertTrue(directlyDecoded.isInstantVideo)
        XCTAssertEqual(directlyDecoded.mimeType, "video/mp4")
        let directlyDecodedResource = try XCTUnwrap(directlyDecoded.resource as? LocalFileReferenceMediaResource)
        XCTAssertEqual(directlyDecodedResource.id, resource.id)
        XCTAssertEqual(directlyDecodedResource.localFilePath, source.path)
        XCTAssertEqual(directlyDecodedResource.size, 4)

        snapshot = try JSONDecoder().decode(SpaceGramHistorySnapshot.self, from: JSONEncoder().encode(snapshot))
        let roundTrippedPayload = try XCTUnwrap(snapshot.media.first?.nativeMediaPayload)
        XCTAssertEqual(roundTrippedPayload, originalPayload)
        let decoded = try XCTUnwrap(PostboxDecoder(buffer: MemoryBuffer(data: roundTrippedPayload)).decodeRootObject() as? TelegramMediaFile)
        XCTAssertEqual(decoded.fileId, fileId)
        XCTAssertTrue(decoded.isInstantVideo)
        XCTAssertEqual(decoded.mimeType, "video/mp4")
        let decodedResource = try XCTUnwrap(decoded.resource as? LocalFileReferenceMediaResource)
        XCTAssertEqual(decodedResource.id, resource.id)
        XCTAssertEqual(decodedResource.localFilePath, source.path)
        XCTAssertEqual(decodedResource.size, 4)

        var item = SpaceGramDeletedMessageOverlayItem(
            originalMessageId: MessageId(peerId: self.peerId, namespace: Namespaces.Message.Cloud, id: 9),
            threadId: nil, snapshot: snapshot, author: nil, chatPeer: nil, hasArchivedMedia: false, stableVersion: 1)
        item.nativeMedia = [decoded]
        let message = item.makeMessage(accountPeerId: self.peerId, deletedLabel: "Deleted", archivedMediaLabel: "Archived", missingMediaLabel: "Media unavailable")
        let rendered = try XCTUnwrap(message.media.first as? TelegramMediaFile)
        XCTAssertEqual(rendered.fileId, fileId)
        XCTAssertTrue(rendered.isInstantVideo)
        XCTAssertEqual(rendered.mimeType, "video/mp4")
        XCTAssertFalse(rendered.fileName?.contains("Media unavailable") == true)
        XCTAssertFalse(rendered.resource is EmptyMediaResource)
        let renderedResource = try XCTUnwrap(rendered.resource as? LocalFileReferenceMediaResource)
        XCTAssertEqual(renderedResource.id, resource.id)
        XCTAssertEqual(renderedResource.localFilePath, source.path)
        XCTAssertEqual(renderedResource.size, 4)
    }
}

private enum SpaceGramOverlayTestError: Error {
    case timedOut(String)
}
