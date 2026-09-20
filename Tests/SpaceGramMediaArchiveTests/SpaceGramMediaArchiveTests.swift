import Foundation
import SpaceGramHistoryStorage
import SpaceGramMediaArchive
import XCTest

final class SpaceGramMediaArchiveTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    private func store(_ bytes: Data, ext: String = "bin", unlink: Bool = false) throws -> (URL, SpaceGramArchivedAsset) {
        let source = directory.appendingPathComponent(UUID().uuidString)
        try bytes.write(to: source)
        let root = SpaceGramMediaArchive.root(mediaBoxPath: directory.appendingPathComponent("media").path)
        let done = expectation(description: "store")
        var assets: [SpaceGramArchivedAsset] = []
        DispatchQueue.global().async {
            guard let capture = SpaceGramMediaArchive.pinCompletedFile(path: source.path, fileName: "fixture." + ext, kind: "file", fileExtension: ext) else {
                XCTFail("A complete regular file must be pinned")
                done.fulfill()
                return
            }
            if unlink {
                do { try FileManager.default.removeItem(at: source) } catch { XCTFail("Fixture unlink failed") }
            }
            SpaceGramMediaArchive.store(root: root, captures: [capture]) {
                assets = $0
                done.fulfill()
            }
        }
        wait(for: [done], timeout: 10)
        return (root, try XCTUnwrap(assets.first))
    }

    func testPinnedFileSurvivesCacheUnlinkAndJSONExtension() throws {
        let bytes = Data("{\"version\":999,\"text\":\"payload, not a manifest\"}".utf8)
        let (root, asset) = try store(bytes, ext: "json", unlink: true)
        let done = expectation(description: "verified preview")
        SpaceGramMediaArchive.preview(root: root, id: asset.id) { result in
            switch result {
            case let .success(lease):
                XCTAssertEqual(try? Data(contentsOf: lease.url), bytes)
            case .failure: XCTFail("Unlink must not destroy a pinned inode; JSON payload is not metadata")
            }
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
    }

    func testBubbleLeaseSurvivesArchiveClearWithoutChangingContent() throws {
        let bytes = Data([1, 3, 5, 7])
        let (root, asset) = try store(bytes)
        let resolved = expectation(description: "bubble lease")
        var lease: SpaceGramArchivedMedia?
        SpaceGramMediaArchive.resolve(root: root, ids: [asset.id]) { resources in
            lease = resources[asset.id]
            resolved.fulfill()
        }
        wait(for: [resolved], timeout: 10)
        let held = try XCTUnwrap(lease)
        let cleared = expectation(description: "archive cleared")
        SpaceGramMediaArchive.clear(root: root) { success in
            XCTAssertTrue(success)
            XCTAssertEqual(try? Data(contentsOf: held.url), bytes)
            cleared.fulfill()
        }
        wait(for: [cleared], timeout: 10)
        let missing = expectation(description: "cleared entries are not resurrected")
        SpaceGramMediaArchive.resolve(root: root, ids: [asset.id]) { resources in
            XCTAssertTrue(resources.isEmpty)
            missing.fulfill()
        }
        wait(for: [missing], timeout: 10)
    }

    func testLegacyArchiveMigrationPreservesHistoryAssetLookupAndPreview() throws {
        let bytes = Data([1, 2, 3, 4])
        let (root, asset) = try store(bytes)
        let legacy = root.deletingLastPathComponent().appendingPathComponent("qwengram-media-v1")
        try FileManager.default.moveItem(at: root, to: legacy)
        let done = expectation(description: "migrated asset")
        SpaceGramMediaArchive.preview(root: root, id: asset.id) { result in
            if case let .success(lease) = result { XCTAssertEqual(try? Data(contentsOf: lease.url), bytes) }
            else { XCTFail("History UUID should still open the same verified payload") }
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(asset.id + ".json").path))
    }

    func testCorruptionIsRejectedEvenWhenSizeMatches() throws {
        let (root, asset) = try store(Data([1, 2, 3, 4]))
        try Data([4, 3, 2, 1]).write(to: root.appendingPathComponent(asset.id + ".data.bin"))
        let done = expectation(description: "corrupt preview")
        SpaceGramMediaArchive.preview(root: root, id: asset.id) { result in
            if case .success = result { XCTFail("A same-size corrupt file must fail SHA-256 verification") }
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
    }

    func testAssetStatesAndClear() throws {
        let (root, asset) = try store(Data([1, 2, 3, 4]))
        let checked = expectation(description: "available state")
        SpaceGramMediaArchive.states(root: root, ids: [asset.id], capturedAt: [asset.id: Int64(Date().timeIntervalSince1970)]) { states in
            if case .some(.available) = states[asset.id] { } else { XCTFail("Stored asset should be available") }
            checked.fulfill()
        }
        wait(for: [checked], timeout: 10)

        try Data([4, 3, 2, 1]).write(to: root.appendingPathComponent(asset.id + ".data.bin"))
        let corrupted = expectation(description: "corrupt state")
        SpaceGramMediaArchive.states(root: root, ids: [asset.id], capturedAt: [:]) { states in
            if case .some(.corrupt) = states[asset.id] { } else { XCTFail("Same-size SHA mismatch must be reported as corrupt") }
            corrupted.fulfill()
        }
        wait(for: [corrupted], timeout: 10)

        let cleared = expectation(description: "clear")
        SpaceGramMediaArchive.clear(root: root) { success in
            XCTAssertTrue(success)
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(asset.id + ".json").path))
            cleared.fulfill()
        }
        wait(for: [cleared], timeout: 10)
    }

    func testMissingPartialSymlinkAndOversizedResourcesAreNotPinned() throws {
        let complete = directory.appendingPathComponent("resource")
        let partial = directory.appendingPathComponent("resource.partial")
        try Data([1]).write(to: partial)
        let link = directory.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: partial)
        let large = directory.appendingPathComponent("large")
        try Data().write(to: large)
        let handle = try FileHandle(forWritingTo: large)
        try handle.truncate(atOffset: UInt64(SpaceGramMediaArchive.maxAssetBytes + 1))
        try handle.close()
        let done = expectation(description: "reject unavailable media")
        DispatchQueue.global().async {
            for url in [complete, link, large] {
                XCTAssertNil(SpaceGramMediaArchive.pinCompletedFile(path: url.path, fileName: "fixture", kind: "file", fileExtension: "bin"))
            }
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
    }

    func testExpirationRemovesMetadataAndPayload() throws {
        let (root, asset) = try store(Data([1, 2, 3]))
        let metadata = root.appendingPathComponent(asset.id + ".json")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: metadata)) as? [String: Any])
        object["timestamp"] = Date().timeIntervalSince1970 - SpaceGramMediaArchive.retention - 10
        try JSONSerialization.data(withJSONObject: object).write(to: metadata)
        let done = expectation(description: "expiry cleanup")
        SpaceGramMediaArchive.list(root: root, ids: [asset.id]) { assets in
            XCTAssertTrue(assets.isEmpty)
            XCTAssertFalse(FileManager.default.fileExists(atPath: metadata.path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(asset.id + ".data.bin").path))
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
    }

    func testAccountIsolationAndFutureManifestPreservation() throws {
        let (root, asset) = try store(Data([1, 2, 3]))
        let otherAccount = directory.appendingPathComponent("otherAccount")
        try FileManager.default.createDirectory(at: otherAccount, withIntermediateDirectories: true)
        let otherRoot = SpaceGramMediaArchive.root(mediaBoxPath: otherAccount.appendingPathComponent("media").path)
        let isolated = expectation(description: "other account")
        SpaceGramMediaArchive.list(root: otherRoot, ids: [asset.id]) { assets in
            XCTAssertTrue(assets.isEmpty)
            isolated.fulfill()
        }
        wait(for: [isolated], timeout: 10)
        let metadata = root.appendingPathComponent(asset.id + ".json")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: metadata)) as? [String: Any])
        object["version"] = 2
        let future = try JSONSerialization.data(withJSONObject: object)
        try future.write(to: metadata)
        let preserved = expectation(description: "newer schema")
        SpaceGramMediaArchive.list(root: root, ids: [asset.id]) { assets in
            XCTAssertTrue(assets.isEmpty)
            XCTAssertEqual(try? Data(contentsOf: metadata), future)
            preserved.fulfill()
        }
        wait(for: [preserved], timeout: 10)
    }

    func testV1HistoryWithoutMediaFieldsStillDecodes() throws {
        let fixture = Data("""
        {"version":1,"key":{"peerId":7,"namespace":0,"id":42},"revisions":[],"events":[{"type":"delete","source":"updateDeleteMessages","reason":"serverDelete","observedTimestamp":1}],"nextRevision":1}
        """.utf8)
        let record = try JSONDecoder().decode(SpaceGramHistoryRecord.self, from: fixture)
        XCTAssertEqual(record.version, 1)
        XCTAssertNil(record.events.first?.mediaAssetIds)
        XCTAssertNil(record.events.first?.mediaCaptureId)
        XCTAssertEqual(try JSONDecoder().decode(SpaceGramHistoryRecord.self, from: JSONEncoder().encode(record)), record)
    }

    func testSharedAssetSurvivesUntilLastReferenceAndUnreadableRecordsBlockDeletion() {
        let shared = UUID().uuidString.lowercased()
        var first = SpaceGramHistoryRecord(key: SpaceGramHistoryMessageKey(peerId: 1, namespace: 0, id: 1))
        var second = SpaceGramHistoryRecord(key: SpaceGramHistoryMessageKey(peerId: 2, namespace: 0, id: 2))
        var event = SpaceGramHistoryEvent(type: .cleanup, source: "test", reason: .mediaArchive, observedTimestamp: 1)
        event.mediaAssetIds = [shared]
        first.events = [event]
        second.events = [event]
        XCTAssertEqual(SpaceGramHistoryStore.detachedAssets(candidates: [shared], remainingRecords: [second], complete: true), [])
        XCTAssertEqual(SpaceGramHistoryStore.detachedAssets(candidates: [shared], remainingRecords: [], complete: false), [])
        XCTAssertEqual(SpaceGramHistoryStore.detachedAssets(candidates: [shared, shared], remainingRecords: [], complete: true), [shared])
        XCTAssertEqual(first.events.first?.mediaAssetIds, second.events.first?.mediaAssetIds)
    }

    func testV2HistoryAssetReferencesPersistAcrossEncoding() throws {
        let assetId = UUID().uuidString.lowercased()
        var record = SpaceGramHistoryRecord(key: SpaceGramHistoryMessageKey(peerId: 7, namespace: 0, id: 42))
        var event = SpaceGramHistoryEvent(type: .cleanup, source: "archive", reason: .mediaArchive, observedTimestamp: 10)
        event.mediaCaptureId = UUID().uuidString.lowercased()
        event.mediaAssetIds = [assetId]
        record.events.append(event)
        let decoded = try JSONDecoder().decode(SpaceGramHistoryRecord.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(decoded.version, SpaceGramHistoryRecord.currentVersion)
        XCTAssertEqual(decoded.events.first?.mediaAssetIds, [assetId])
        XCTAssertEqual(decoded.events.first?.mediaCaptureId, event.mediaCaptureId)
    }

    func testPolicyPresetsAndManualAgeCleanup() throws {
        XCTAssertEqual(SpaceGramMediaArchivePolicy.storagePresets, [256, 512, 1024, 2048].map { Int64($0) * 1024 * 1024 })
        XCTAssertEqual(SpaceGramMediaArchivePolicy.retentionPresets, [7, 30, 90])
        let (root, asset) = try store(Data([1, 2, 3]))
        let policy = SpaceGramMediaArchivePolicy(storageLimitBytes: 256 * 1024 * 1024, retentionDays: 7, automaticCleanup: false)
        let configured = expectation(description: "policy")
        SpaceGramMediaArchive.setPolicy(root: root, policy: policy) { success in
            XCTAssertTrue(success)
            configured.fulfill()
        }
        wait(for: [configured], timeout: 10)
        let metadata = root.appendingPathComponent(asset.id + ".json")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: metadata)) as? [String: Any])
        object["timestamp"] = Date().timeIntervalSince1970 - 8 * 24 * 60 * 60
        try JSONSerialization.data(withJSONObject: object).write(to: metadata)
        let retained = expectation(description: "automatic cleanup disabled")
        SpaceGramMediaArchive.list(root: root, ids: [asset.id]) { values in
            XCTAssertEqual(values.count, 1)
            retained.fulfill()
        }
        wait(for: [retained], timeout: 10)
        let cleaned = expectation(description: "manual cleanup")
        SpaceGramMediaArchive.cleanExpired(root: root, referencedIds: [asset.id], referencesComplete: true) { success in
            XCTAssertTrue(success)
            XCTAssertFalse(FileManager.default.fileExists(atPath: metadata.path))
            cleaned.fulfill()
        }
        wait(for: [cleaned], timeout: 10)
    }

    func testOrphanCleanupAndMissingOrCorruptStates() throws {
        let (root, asset) = try store(Data([1, 2, 3]))
        let metadata = root.appendingPathComponent(asset.id + ".json")
        let payload = root.appendingPathComponent(asset.id + ".data.bin")
        try FileManager.default.removeItem(at: payload)
        let missing = expectation(description: "missing payload")
        SpaceGramMediaArchive.states(root: root, ids: [asset.id], capturedAt: [:]) { states in
            if case .some(.missing) = states[asset.id] { } else { XCTFail("Missing payload must be visible") }
            missing.fulfill()
        }
        wait(for: [missing], timeout: 10)
        try Data([1, 2, 3]).write(to: payload)
        try Data("invalid".utf8).write(to: metadata)
        let corrupt = expectation(description: "corrupt manifest")
        SpaceGramMediaArchive.states(root: root, ids: [asset.id], capturedAt: [:]) { states in
            if case .some(.corrupt) = states[asset.id] { } else { XCTFail("Corrupt manifest must be visible") }
            corrupt.fulfill()
        }
        wait(for: [corrupt], timeout: 10)

        let (orphanRoot, orphan) = try store(Data([4, 5, 6]))
        let orphanMetadata = orphanRoot.appendingPathComponent(orphan.id + ".json")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: orphanMetadata)) as? [String: Any])
        object["timestamp"] = Date().timeIntervalSince1970 - 10 * 60
        try JSONSerialization.data(withJSONObject: object).write(to: orphanMetadata)
        SpaceGramMediaArchive.reconcile(root: orphanRoot, referencedIds: [], referencesComplete: true)
        let reconciled = expectation(description: "reconciled")
        SpaceGramMediaArchive.usage(root: orphanRoot) { result in
            if case let .success(usage) = result { XCTAssertEqual(usage.assetCount, 0) }
            else { XCTFail("Archive should remain readable") }
            XCTAssertFalse(FileManager.default.fileExists(atPath: orphanMetadata.path))
            reconciled.fulfill()
        }
        wait(for: [reconciled], timeout: 10)
    }

    func testSizeAndCountLimitsEvictOldestAssets() throws {
        func asset(_ index: Int, bytes: Int64) throws -> SpaceGramArchivedAsset {
            let fixture: [String: Any] = [
                "version": 1, "id": UUID().uuidString.lowercased(), "fileName": "test", "fileExtension": "bin",
                "kind": "file", "bytes": bytes, "timestamp": Double(index), "sha256": String(repeating: "0", count: 64)
            ]
            return try JSONDecoder().decode(SpaceGramArchivedAsset.self, from: JSONSerialization.data(withJSONObject: fixture))
        }
        let oldest = try asset(1, bytes: 100)
        let middle = try asset(2, bytes: 100)
        let newest = try asset(3, bytes: 100)
        XCTAssertEqual(SpaceGramMediaArchive.retainedAssets([newest, oldest, middle], storageLimitBytes: 200).map { $0.id }, [middle.id, newest.id])
        XCTAssertEqual(SpaceGramMediaArchive.retainedAssets([newest, oldest, middle], storageLimitBytes: 1000, maxCount: 1).map { $0.id }, [newest.id])
    }

    func testAccountUsageAndCleanupStayIsolated() throws {
        let (firstRoot, firstAsset) = try store(Data([1, 2, 3]))
        let secondDirectory = directory.appendingPathComponent("second-account")
        try FileManager.default.createDirectory(at: secondDirectory, withIntermediateDirectories: true)
        let secondRoot = SpaceGramMediaArchive.root(mediaBoxPath: secondDirectory.appendingPathComponent("media").path)
        let checked = expectation(description: "isolated usage")
        SpaceGramMediaArchive.usage(root: secondRoot) { result in
            if case let .success(usage) = result {
                XCTAssertEqual(usage.bytes, 0)
                XCTAssertEqual(usage.assetCount, 0)
            } else { XCTFail("Second account usage unavailable") }
            checked.fulfill()
        }
        wait(for: [checked], timeout: 10)
        let cleared = expectation(description: "isolated cleanup")
        SpaceGramMediaArchive.clear(root: secondRoot) { success in
            XCTAssertTrue(success)
            XCTAssertTrue(FileManager.default.fileExists(atPath: firstRoot.appendingPathComponent(firstAsset.id + ".json").path))
            cleared.fulfill()
        }
        wait(for: [cleared], timeout: 10)
    }
}
