import Postbox
import SpaceGramHistoryOverlay
import SpaceGramHistoryStorage
import TelegramCore
import XCTest

final class SpaceGramDeletedMessageOverlayTests: XCTestCase {
    private let peerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(42))

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
