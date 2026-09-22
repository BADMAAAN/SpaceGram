import SpaceGramHistoryStorage
import XCTest

final class SpaceGramReceivedMediaObservationTests: XCTestCase {
    func testSharedCompletedResourceTargetsEveryMessageOnce() {
        var firstSnapshot = SpaceGramHistorySnapshot(text: "", originalMessageTimestamp: 1)
        var firstMedia = SpaceGramHistoryMediaMetadata(type: "image")
        firstMedia.resourceIds = ["shared", "shared"]
        firstSnapshot.media = [firstMedia]

        var secondSnapshot = SpaceGramHistorySnapshot(text: "", originalMessageTimestamp: 2)
        var secondMedia = SpaceGramHistoryMediaMetadata(type: "image")
        secondMedia.resourceIds = ["shared"]
        secondSnapshot.media = [secondMedia]

        let first = SpaceGramReceivedMessageSnapshot(
            key: SpaceGramHistoryMessageKey(peerId: 1, namespace: 0, id: 10),
            threadId: nil,
            snapshot: firstSnapshot
        )
        let second = SpaceGramReceivedMessageSnapshot(
            key: SpaceGramHistoryMessageKey(peerId: 1, namespace: 0, id: 11),
            threadId: nil,
            snapshot: secondSnapshot
        )

        let targets = SpaceGramMessageSnapshotStore.targetsByResourceId([first, second])

        XCTAssertEqual(targets["shared"]?.map(\.key), [first.key, second.key])
    }

    func testMissingResourceIdsDoNotCreateReadyTargets() {
        let snapshot = SpaceGramReceivedMessageSnapshot(
            key: SpaceGramHistoryMessageKey(peerId: 1, namespace: 0, id: 12),
            threadId: nil,
            snapshot: SpaceGramHistorySnapshot(text: "", originalMessageTimestamp: 3)
        )

        XCTAssertTrue(SpaceGramMessageSnapshotStore.targetsByResourceId([snapshot]).isEmpty)
    }
}
