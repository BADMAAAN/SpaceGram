import Foundation
import SpaceGramHistoryStorage
import XCTest

final class SpaceGramHistoryQueryTests: XCTestCase {
    private func record() -> SpaceGramHistoryRecord {
        var record = SpaceGramHistoryRecord(key: SpaceGramHistoryMessageKey(peerId: 7, namespace: 0, id: 42))
        var snapshot = SpaceGramHistorySnapshot(text: "Привет SpaceGram", originalMessageTimestamp: 1)
        var media = SpaceGramHistoryMediaMetadata(type: "file")
        media.filename = "Report.pdf"
        snapshot.media = [media]
        record.revisions = [SpaceGramHistoryRevision(number: 1, observedTimestamp: 2, snapshot: snapshot)]
        record.events = [SpaceGramHistoryEvent(type: .edit, source: "fixture", reason: .edit, observedTimestamp: 2, revisionNumber: 1)]
        record.nextRevision = 2
        return record
    }

    func testKindAndPeerFiltersCompose() {
        let record = record()
        XCTAssertTrue(SpaceGramHistoryQuery.matches(record, kind: .edited, peerId: 7))
        XCTAssertFalse(SpaceGramHistoryQuery.matches(record, kind: .deleted))
        XCTAssertFalse(SpaceGramHistoryQuery.matches(record, peerId: 8))
        XCTAssertTrue(SpaceGramHistoryQuery.matches(record, kind: .media))
    }

    func testSearchIncludesOldTextFilenamesAndPeers() {
        let record = record()
        XCTAssertTrue(SpaceGramHistoryQuery.matches(record, query: "  привет  "))
        XCTAssertTrue(SpaceGramHistoryQuery.matches(record, query: "report.PDF"))
        XCTAssertTrue(SpaceGramHistoryQuery.matches(record, query: "alice", peerTitles: ["Alice"]))
        XCTAssertFalse(SpaceGramHistoryQuery.matches(record, query: "absent"))
    }

    func testMediaFilterRetainsMissingAssetEvidence() {
        var record = record()
        record.revisions = []
        record.events[0].mediaAssetIds = [UUID().uuidString]
        XCTAssertTrue(SpaceGramHistoryQuery.matches(record, kind: .media))
        record.events[0].mediaAssetIds = nil
        XCTAssertFalse(SpaceGramHistoryQuery.matches(record, kind: .media))
    }

    func testPostboxCollectionAndPackedMessageIdentityStayStable() {
        XCTAssertEqual(SpaceGramHistoryCollection.id, 1009)
        XCTAssertEqual(record().key.binaryKey, Data([0, 0, 0, 0, 0, 0, 0, 7, 0, 0, 0, 0, 0, 0, 0, 42]))
    }
}
