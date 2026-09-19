import Foundation
import QwengramHistoryStorage
import QwengramMediaArchive
import XCTest

final class QwengramMediaArchiveTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    private func store(_ bytes: Data, ext: String = "bin", unlink: Bool = false) throws -> (URL, QwengramArchivedAsset) {
        let source = directory.appendingPathComponent(UUID().uuidString)
        try bytes.write(to: source)
        let root = QwengramMediaArchive.root(mediaBoxPath: directory.appendingPathComponent("media").path)
        let done = expectation(description: "store")
        var assets: [QwengramArchivedAsset] = []
        DispatchQueue.global().async {
            guard let capture = QwengramMediaArchive.pinCompletedFile(path: source.path, fileName: "fixture." + ext, kind: "file", fileExtension: ext) else {
                XCTFail("A complete regular file must be pinned")
                done.fulfill()
                return
            }
            if unlink {
                do { try FileManager.default.removeItem(at: source) } catch { XCTFail("Fixture unlink failed") }
            }
            QwengramMediaArchive.store(root: root, captures: [capture]) {
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
        QwengramMediaArchive.preview(root: root, id: asset.id) { result in
            switch result {
            case let .success(lease):
                XCTAssertEqual(try? Data(contentsOf: lease.url), bytes)
            case .failure: XCTFail("Unlink must not destroy a pinned inode; JSON payload is not metadata")
            }
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
    }

    func testCorruptionIsRejectedEvenWhenSizeMatches() throws {
        let (root, asset) = try store(Data([1, 2, 3, 4]))
        try Data([4, 3, 2, 1]).write(to: root.appendingPathComponent(asset.id + ".data.bin"))
        let done = expectation(description: "corrupt preview")
        QwengramMediaArchive.preview(root: root, id: asset.id) { result in
            if case .success = result { XCTFail("A same-size corrupt file must fail SHA-256 verification") }
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
    }

    func testAssetStatesAndClear() throws {
        let (root, asset) = try store(Data([1, 2, 3, 4]))
        let checked = expectation(description: "available state")
        QwengramMediaArchive.states(root: root, ids: [asset.id], capturedAt: [asset.id: Int64(Date().timeIntervalSince1970)]) { states in
            if case .some(.available) = states[asset.id] { } else { XCTFail("Stored asset should be available") }
            checked.fulfill()
        }
        wait(for: [checked], timeout: 10)

        try Data([4, 3, 2, 1]).write(to: root.appendingPathComponent(asset.id + ".data.bin"))
        let corrupted = expectation(description: "corrupt state")
        QwengramMediaArchive.states(root: root, ids: [asset.id], capturedAt: [:]) { states in
            if case .some(.corrupt) = states[asset.id] { } else { XCTFail("Same-size SHA mismatch must be reported as corrupt") }
            corrupted.fulfill()
        }
        wait(for: [corrupted], timeout: 10)

        let cleared = expectation(description: "clear")
        QwengramMediaArchive.clear(root: root) { success in
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
        try handle.truncate(atOffset: UInt64(QwengramMediaArchive.maxAssetBytes + 1))
        try handle.close()
        let done = expectation(description: "reject unavailable media")
        DispatchQueue.global().async {
            for url in [complete, link, large] {
                XCTAssertNil(QwengramMediaArchive.pinCompletedFile(path: url.path, fileName: "fixture", kind: "file", fileExtension: "bin"))
            }
            done.fulfill()
        }
        wait(for: [done], timeout: 10)
    }

    func testExpirationRemovesMetadataAndPayload() throws {
        let (root, asset) = try store(Data([1, 2, 3]))
        let metadata = root.appendingPathComponent(asset.id + ".json")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: metadata)) as? [String: Any])
        object["timestamp"] = Date().timeIntervalSince1970 - QwengramMediaArchive.retention - 10
        try JSONSerialization.data(withJSONObject: object).write(to: metadata)
        let done = expectation(description: "expiry cleanup")
        QwengramMediaArchive.list(root: root, ids: [asset.id]) { assets in
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
        let otherRoot = QwengramMediaArchive.root(mediaBoxPath: otherAccount.appendingPathComponent("media").path)
        let isolated = expectation(description: "other account")
        QwengramMediaArchive.list(root: otherRoot, ids: [asset.id]) { assets in
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
        QwengramMediaArchive.list(root: root, ids: [asset.id]) { assets in
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
        let record = try JSONDecoder().decode(QwengramHistoryRecord.self, from: fixture)
        XCTAssertEqual(record.version, 1)
        XCTAssertNil(record.events.first?.mediaAssetIds)
        XCTAssertNil(record.events.first?.mediaCaptureId)
        XCTAssertEqual(try JSONDecoder().decode(QwengramHistoryRecord.self, from: JSONEncoder().encode(record)), record)
    }

    func testSharedAssetSurvivesUntilLastReferenceAndUnreadableRecordsBlockDeletion() {
        let shared = UUID().uuidString.lowercased()
        var first = QwengramHistoryRecord(key: QwengramHistoryMessageKey(peerId: 1, namespace: 0, id: 1))
        var second = QwengramHistoryRecord(key: QwengramHistoryMessageKey(peerId: 2, namespace: 0, id: 2))
        var event = QwengramHistoryEvent(type: .cleanup, source: "test", reason: .mediaArchive, observedTimestamp: 1)
        event.mediaAssetIds = [shared]
        first.events = [event]
        second.events = [event]
        XCTAssertEqual(QwengramHistoryStore.detachedAssets(candidates: [shared], remainingRecords: [second], complete: true), [])
        XCTAssertEqual(QwengramHistoryStore.detachedAssets(candidates: [shared], remainingRecords: [], complete: false), [])
        XCTAssertEqual(QwengramHistoryStore.detachedAssets(candidates: [shared, shared], remainingRecords: [], complete: true), [shared])
        XCTAssertEqual(first.events.first?.mediaAssetIds, second.events.first?.mediaAssetIds)
    }

    func testV2HistoryAssetReferencesPersistAcrossEncoding() throws {
        let assetId = UUID().uuidString.lowercased()
        var record = QwengramHistoryRecord(key: QwengramHistoryMessageKey(peerId: 7, namespace: 0, id: 42))
        var event = QwengramHistoryEvent(type: .cleanup, source: "archive", reason: .mediaArchive, observedTimestamp: 10)
        event.mediaCaptureId = UUID().uuidString.lowercased()
        event.mediaAssetIds = [assetId]
        record.events.append(event)
        let decoded = try JSONDecoder().decode(QwengramHistoryRecord.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(decoded.version, QwengramHistoryRecord.currentVersion)
        XCTAssertEqual(decoded.events.first?.mediaAssetIds, [assetId])
        XCTAssertEqual(decoded.events.first?.mediaCaptureId, event.mediaCaptureId)
    }

    func testPolicyPresetsAndManualAgeCleanup() throws {
        XCTAssertEqual(QwengramMediaArchivePolicy.storagePresets, [256, 512, 1024, 2048].map { Int64($0) * 1024 * 1024 })
        XCTAssertEqual(QwengramMediaArchivePolicy.retentionPresets, [7, 30, 90])
        let (root, asset) = try store(Data([1, 2, 3]))
        let policy = QwengramMediaArchivePolicy(storageLimitBytes: 256 * 1024 * 1024, retentionDays: 7, automaticCleanup: false)
        let configured = expectation(description: "policy")
        QwengramMediaArchive.setPolicy(root: root, policy: policy) { success in
            XCTAssertTrue(success)
            configured.fulfill()
        }
        wait(for: [configured], timeout: 10)
        let metadata = root.appendingPathComponent(asset.id + ".json")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: metadata)) as? [String: Any])
        object["timestamp"] = Date().timeIntervalSince1970 - 8 * 24 * 60 * 60
        try JSONSerialization.data(withJSONObject: object).write(to: metadata)
        let retained = expectation(description: "automatic cleanup disabled")
        QwengramMediaArchive.list(root: root, ids: [asset.id]) { values in
            XCTAssertEqual(values.count, 1)
            retained.fulfill()
        }
        wait(for: [retained], timeout: 10)
        let cleaned = expectation(description: "manual cleanup")
        QwengramMediaArchive.cleanExpired(root: root, referencedIds: [asset.id], referencesComplete: true) { success in
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
        QwengramMediaArchive.states(root: root, ids: [asset.id], capturedAt: [:]) { states in
            if case .some(.missing) = states[asset.id] { } else { XCTFail("Missing payload must be visible") }
            missing.fulfill()
        }
        wait(for: [missing], timeout: 10)
        try Data([1, 2, 3]).write(to: payload)
        try Data("invalid".utf8).write(to: metadata)
        let corrupt = expectation(description: "corrupt manifest")
        QwengramMediaArchive.states(root: root, ids: [asset.id], capturedAt: [:]) { states in
            if case .some(.corrupt) = states[asset.id] { } else { XCTFail("Corrupt manifest must be visible") }
            corrupt.fulfill()
        }
        wait(for: [corrupt], timeout: 10)

        let (orphanRoot, orphan) = try store(Data([4, 5, 6]))
        let orphanMetadata = orphanRoot.appendingPathComponent(orphan.id + ".json")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: orphanMetadata)) as? [String: Any])
        object["timestamp"] = Date().timeIntervalSince1970 - 10 * 60
        try JSONSerialization.data(withJSONObject: object).write(to: orphanMetadata)
        QwengramMediaArchive.reconcile(root: orphanRoot, referencedIds: [], referencesComplete: true)
        let reconciled = expectation(description: "reconciled")
        QwengramMediaArchive.usage(root: orphanRoot) { result in
            if case let .success(usage) = result { XCTAssertEqual(usage.assetCount, 0) }
            else { XCTFail("Archive should remain readable") }
            XCTAssertFalse(FileManager.default.fileExists(atPath: orphanMetadata.path))
            reconciled.fulfill()
        }
        wait(for: [reconciled], timeout: 10)
    }

    func testSizeAndCountLimitsEvictOldestAssets() throws {
        func asset(_ index: Int, bytes: Int64) throws -> QwengramArchivedAsset {
            let fixture: [String: Any] = [
                "version": 1, "id": UUID().uuidString.lowercased(), "fileName": "test", "fileExtension": "bin",
                "kind": "file", "bytes": bytes, "timestamp": Double(index), "sha256": String(repeating: "0", count: 64)
            ]
            return try JSONDecoder().decode(QwengramArchivedAsset.self, from: JSONSerialization.data(withJSONObject: fixture))
        }
        let oldest = try asset(1, bytes: 100)
        let middle = try asset(2, bytes: 100)
        let newest = try asset(3, bytes: 100)
        XCTAssertEqual(QwengramMediaArchive.retainedAssets([newest, oldest, middle], storageLimitBytes: 200).map { $0.id }, [middle.id, newest.id])
        XCTAssertEqual(QwengramMediaArchive.retainedAssets([newest, oldest, middle], storageLimitBytes: 1000, maxCount: 1).map { $0.id }, [newest.id])
    }

    func testAccountUsageAndCleanupStayIsolated() throws {
        let (firstRoot, firstAsset) = try store(Data([1, 2, 3]))
        let secondDirectory = directory.appendingPathComponent("second-account")
        try FileManager.default.createDirectory(at: secondDirectory, withIntermediateDirectories: true)
        let secondRoot = QwengramMediaArchive.root(mediaBoxPath: secondDirectory.appendingPathComponent("media").path)
        let checked = expectation(description: "isolated usage")
        QwengramMediaArchive.usage(root: secondRoot) { result in
            if case let .success(usage) = result {
                XCTAssertEqual(usage.bytes, 0)
                XCTAssertEqual(usage.assetCount, 0)
            } else { XCTFail("Second account usage unavailable") }
            checked.fulfill()
        }
        wait(for: [checked], timeout: 10)
        let cleared = expectation(description: "isolated cleanup")
        QwengramMediaArchive.clear(root: secondRoot) { success in
            XCTAssertTrue(success)
            XCTAssertTrue(FileManager.default.fileExists(atPath: firstRoot.appendingPathComponent(firstAsset.id + ".json").path))
            cleared.fulfill()
        }
        wait(for: [cleared], timeout: 10)
    }
}
