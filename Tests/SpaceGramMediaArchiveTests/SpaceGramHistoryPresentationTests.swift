import Foundation
import SpaceGramHistoryStorage
import XCTest

final class SpaceGramHistoryPresentationTests: XCTestCase {
    private func record() -> SpaceGramHistoryRecord {
        var record = SpaceGramHistoryRecord(key: SpaceGramHistoryMessageKey(peerId: 7, namespace: 0, id: 42))
        var first = SpaceGramHistorySnapshot(text: "Before", originalMessageTimestamp: 10)
        first.entities = [SpaceGramHistoryEntity(type: "bold", offset: 0, length: 6)]
        record.revisions = [
            SpaceGramHistoryRevision(number: 1, observedTimestamp: 20, snapshot: first),
            SpaceGramHistoryRevision(number: 2, observedTimestamp: 30, snapshot: SpaceGramHistorySnapshot(text: "After", originalMessageTimestamp: 10))
        ]
        record.events = [
            SpaceGramHistoryEvent(type: .edit, source: "fixture", reason: .edit, observedTimestamp: 20, revisionNumber: 1),
            SpaceGramHistoryEvent(type: .delete, source: "fixture", reason: .serverDelete, observedTimestamp: 30, revisionNumber: 2)
        ]
        record.events[1].mediaAssetIds = ["fixture-asset"]
        return record
    }

    func testDeletedPresentationRetainsTextAndAssetReference() {
        let record = record()
        XCTAssertEqual(SpaceGramHistoryPresentationModel.deletedSnapshot(record)?.text, "After")
        let item = SpaceGramHistoryPresentationModel.timeline(record).last
        XCTAssertEqual(item?.event?.mediaAssetIds, ["fixture-asset"])
        XCTAssertEqual(item?.timestamp, 30)
    }

    func testExpiredDeletedRevisionDoesNotShowUnrelatedText() {
        var record = record()
        record.revisions.removeLast()
        XCTAssertNil(SpaceGramHistoryPresentationModel.deletedSnapshot(record))
        XCTAssertNil(SpaceGramHistoryPresentationModel.timeline(record).last?.revision)
        XCTAssertTrue(SpaceGramHistoryQuery.matches(record, kind: .deleted))
    }

    func testEditMappingPreservesFormattingAndOrder() {
        var record = record()
        record.events.reverse()
        let items = SpaceGramHistoryPresentationModel.timeline(record)
        XCTAssertEqual(items.first?.revision?.snapshot.text, "Before")
        XCTAssertEqual(items.first?.revision?.snapshot.entities.first?.type, "bold")
        XCTAssertEqual(items.first?.eventIndex, 1)
        XCTAssertEqual(items.last?.timestamp, 30)
    }

    func testUnpairedRevisionsRemainVisibleWithoutInventedEvent() {
        var record = record()
        record.events.removeFirst()
        let item = SpaceGramHistoryPresentationModel.timeline(record).first
        XCTAssertNil(item?.event)
        XCTAssertEqual(item?.revision?.number, 1)
    }

    func testEditViewerExcludesDeleteAndCaptureVersionsAndPreservesRepeatedText() {
        var record = record()
        record.revisions.append(SpaceGramHistoryRevision(number: 3, observedTimestamp: 20, snapshot: record.revisions[0].snapshot))
        record.events.append(SpaceGramHistoryEvent(type: .edit, source: "fixture", reason: .edit, observedTimestamp: 20, revisionNumber: 3))
        record.revisions.reverse()
        let edits = SpaceGramHistoryPresentationModel.editRevisions(record)
        XCTAssertEqual(edits.map(\.number), [1, 3])
        XCTAssertEqual(edits.map { $0.snapshot.text }, ["Before", "Before"])
    }

    func testABCEditHistoryContainsOnlyABEvenAfterCapturingCurrentMedia() {
        var record = record()
        record.revisions[0] = SpaceGramHistoryRevision(number: 1, observedTimestamp: 20, snapshot: SpaceGramHistorySnapshot(text: "A", originalMessageTimestamp: 10))
        record.revisions[1] = SpaceGramHistoryRevision(number: 2, observedTimestamp: 30, snapshot: SpaceGramHistorySnapshot(text: "B", originalMessageTimestamp: 10))
        record.events[1] = SpaceGramHistoryEvent(type: .edit, source: "fixture", reason: .edit, observedTimestamp: 30, revisionNumber: 2)
        record.revisions.append(SpaceGramHistoryRevision(number: 3, observedTimestamp: 40, snapshot: SpaceGramHistorySnapshot(text: "C", originalMessageTimestamp: 10)))
        record.events.append(SpaceGramHistoryEvent(type: .cleanup, source: "fixture", reason: .mediaArchive, observedTimestamp: 40, revisionNumber: 3))
        XCTAssertEqual(SpaceGramHistoryPresentationModel.editRevisions(record).map { $0.snapshot.text }, ["A", "B"])
    }

    func testReceivedSnapshotRoundTripKeepsMessageIdentityAndFormatting() throws {
        let record = record()
        let value = SpaceGramReceivedMessageSnapshot(key: record.key, threadId: 77, snapshot: record.revisions[0].snapshot)
        let decoded = try JSONDecoder().decode(SpaceGramReceivedMessageSnapshot.self, from: JSONEncoder().encode(value))
        XCTAssertEqual(value, decoded)
        XCTAssertEqual(decoded.threadId, 77)
        XCTAssertEqual(decoded.snapshot.entities.first?.type, "bold")
        XCTAssertNotEqual(SpaceGramMessageSnapshotStore.collectionId, SpaceGramHistoryCollection.id)
    }
}
