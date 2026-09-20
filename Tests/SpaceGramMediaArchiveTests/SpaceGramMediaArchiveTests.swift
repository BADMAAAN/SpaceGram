import Foundation
import SpaceGramHistoryStorage
import SpaceGramMediaArchive
import XCTest

private final class SpaceGramTestCallbackValue<Value> {
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

private enum SpaceGramMediaArchiveFixtureError: Error {
    case captureFailed
    case unlinkFailed
    case timedOut(String)
}

final class SpaceGramMediaArchiveTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        guard let directory = self.directory else { return }
        let root = SpaceGramMediaArchive.root(mediaBoxPath: directory.appendingPathComponent("media").path)
        _ = try waitForCallback("archive queue drain") { SpaceGramMediaArchive.usage(root: root, completion: $0) }
        self.directory = nil
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    private func waitForCallback<Value>(_ description: String, timeout: TimeInterval = 10.0, _ operation: (@escaping (Value) -> Void) -> Void) throws -> Value {
        let value = SpaceGramTestCallbackValue<Value>()
        let completed = DispatchSemaphore(value: 0)
        operation {
            value.store($0)
            completed.signal()
        }
        guard completed.wait(timeout: .now() + timeout) == .success else {
            throw SpaceGramMediaArchiveFixtureError.timedOut(description)
        }
        return try XCTUnwrap(value.load(), "Missing callback value for \(description)")
    }

    private func store(_ bytes: Data, ext: String = "bin", unlink: Bool = false) throws -> (URL, SpaceGramArchivedAsset) {
        let source = directory.appendingPathComponent(UUID().uuidString)
        try bytes.write(to: source)
        let root = SpaceGramMediaArchive.root(mediaBoxPath: directory.appendingPathComponent("media").path)
        let result: Result<[SpaceGramArchivedAsset], SpaceGramMediaArchiveFixtureError> = try waitForCallback("store") { complete in
            DispatchQueue.global().async {
                guard let capture = SpaceGramMediaArchive.pinCompletedFile(path: source.path, fileName: "fixture." + ext, kind: "file", fileExtension: ext) else {
                    complete(.failure(.captureFailed))
                    return
                }
                if unlink {
                    do {
                        try FileManager.default.removeItem(at: source)
                    } catch {
                        complete(.failure(.unlinkFailed))
                        return
                    }
                }
                SpaceGramMediaArchive.store(root: root, captures: [capture]) { complete(.success($0)) }
            }
        }
        let assets = try result.get()
        return (root, try XCTUnwrap(assets.first))
    }

    func testPinnedFileSurvivesCacheUnlinkAndJSONExtension() throws {
        let bytes = Data("{\"version\":999,\"text\":\"payload, not a manifest\"}".utf8)
        let (root, asset) = try store(bytes, ext: "json", unlink: true)
        let result = try waitForCallback("verified preview") {
            SpaceGramMediaArchive.preview(root: root, id: asset.id, completion: $0)
        }
        let lease = try result.get()
        XCTAssertEqual(try? Data(contentsOf: lease.url), bytes)
    }

    func testResourceReferenceDeduplicatesAndRetainsBeforeDeletionButHonorsExpiry() throws {
        let source = directory.appendingPathComponent("completed-sticker")
        try Data([1, 2, 3, 4]).write(to: source)
        let root = SpaceGramMediaArchive.root(mediaBoxPath: directory.appendingPathComponent("media").path)
        var storedIds: [String] = []
        for _ in 0 ..< 2 {
            let capture = try XCTUnwrap(SpaceGramMediaArchive.pinCompletedFile(path: source.path, fileName: "sticker.webp", kind: "sticker", fileExtension: "webp"))
            capture.resourceId = "cloud-resource-fixture"
            let assets = try waitForCallback("deduplicate repeated completion") {
                SpaceGramMediaArchive.store(root: root, captures: [capture], completion: $0)
            }
            XCTAssertEqual(assets.count, 1)
            storedIds.append(contentsOf: assets.map(\.id))
        }
        XCTAssertEqual(Set(storedIds).count, 1)
        let metadata = root.appendingPathComponent(try XCTUnwrap(storedIds.first) + ".json")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: metadata)) as? [String: Any])
        object["timestamp"] = Date().timeIntervalSince1970 - 10 * 60
        try JSONSerialization.data(withJSONObject: object).write(to: metadata)
        SpaceGramMediaArchive.reconcile(root: root, referencedIds: [], referencesComplete: true)
        let retained = try waitForCallback("resource reference survives before any delete event") {
            SpaceGramMediaArchive.resolve(root: root, ids: [], resourceIds: ["cloud-resource-fixture"], completion: $0)
        }
        XCTAssertEqual(retained.count, 1)
        object["timestamp"] = Date().timeIntervalSince1970 - 31 * 24 * 60 * 60
        try JSONSerialization.data(withJSONObject: object).write(to: metadata)
        let expired = try waitForCallback("stable resource reference does not bypass retention") {
            SpaceGramMediaArchive.resolve(root: root, ids: [], resourceIds: ["cloud-resource-fixture"], completion: $0)
        }
        XCTAssertTrue(expired.isEmpty)
    }

    func testBubbleLeaseSurvivesArchiveClearWithoutChangingContent() throws {
        let bytes = Data([1, 3, 5, 7])
        let (root, asset) = try store(bytes)
        let resources = try waitForCallback("bubble lease") {
            SpaceGramMediaArchive.resolve(root: root, ids: [asset.id], completion: $0)
        }
        let held = try XCTUnwrap(resources[asset.id])
        let cleared = try waitForCallback("archive cleared") {
            SpaceGramMediaArchive.clear(root: root, completion: $0)
        }
        XCTAssertTrue(cleared)
        XCTAssertEqual(try? Data(contentsOf: held.url), bytes)
        let missing = try waitForCallback("cleared entries are not resurrected") {
            SpaceGramMediaArchive.resolve(root: root, ids: [asset.id], completion: $0)
        }
        XCTAssertTrue(missing.isEmpty)
    }

    func testLegacyArchiveMigrationPreservesHistoryAssetLookupAndPreview() throws {
        let bytes = Data([1, 2, 3, 4])
        let (root, asset) = try store(bytes)
        let legacy = root.deletingLastPathComponent().appendingPathComponent("qwengram-media-v1")
        try FileManager.default.moveItem(at: root, to: legacy)
        let result = try waitForCallback("migrated asset") {
            SpaceGramMediaArchive.preview(root: root, id: asset.id, completion: $0)
        }
        let lease = try result.get()
        XCTAssertEqual(try? Data(contentsOf: lease.url), bytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(asset.id + ".json").path))
    }

    func testCorruptionIsRejectedEvenWhenSizeMatches() throws {
        let (root, asset) = try store(Data([1, 2, 3, 4]))
        try Data([4, 3, 2, 1]).write(to: root.appendingPathComponent(asset.id + ".data.bin"))
        let result = try waitForCallback("corrupt preview") {
            SpaceGramMediaArchive.preview(root: root, id: asset.id, completion: $0)
        }
        guard case .failure = result else { return XCTFail("A same-size corrupt file must fail SHA-256 verification") }
    }

    func testAssetStatesAndClear() throws {
        let (root, asset) = try store(Data([1, 2, 3, 4]))
        let available = try waitForCallback("available state") {
            SpaceGramMediaArchive.states(root: root, ids: [asset.id], capturedAt: [asset.id: Int64(Date().timeIntervalSince1970)], completion: $0)
        }
        guard case .some(.available) = available[asset.id] else { return XCTFail("Stored asset should be available") }

        try Data([4, 3, 2, 1]).write(to: root.appendingPathComponent(asset.id + ".data.bin"))
        let corrupted = try waitForCallback("corrupt state") {
            SpaceGramMediaArchive.states(root: root, ids: [asset.id], capturedAt: [:], completion: $0)
        }
        guard case .some(.corrupt) = corrupted[asset.id] else { return XCTFail("Same-size SHA mismatch must be reported as corrupt") }

        let cleared = try waitForCallback("clear") {
            SpaceGramMediaArchive.clear(root: root, completion: $0)
        }
        XCTAssertTrue(cleared)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(asset.id + ".json").path))
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
        let captures: [SpaceGramMediaCapture?] = try waitForCallback("reject unavailable media") { completeResult in
            DispatchQueue.global().async {
                completeResult([complete, link, large].map {
                    SpaceGramMediaArchive.pinCompletedFile(path: $0.path, fileName: "fixture", kind: "file", fileExtension: "bin")
                })
            }
        }
        XCTAssertTrue(captures.allSatisfy { $0 == nil })
    }

    func testExpirationRemovesMetadataAndPayload() throws {
        let (root, asset) = try store(Data([1, 2, 3]))
        let metadata = root.appendingPathComponent(asset.id + ".json")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: metadata)) as? [String: Any])
        object["timestamp"] = Date().timeIntervalSince1970 - SpaceGramMediaArchive.retention - 10
        try JSONSerialization.data(withJSONObject: object).write(to: metadata)
        let assets = try waitForCallback("expiry cleanup") {
            SpaceGramMediaArchive.list(root: root, ids: [asset.id], completion: $0)
        }
        XCTAssertTrue(assets.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: metadata.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(asset.id + ".data.bin").path))
    }

    func testAccountIsolationAndFutureManifestPreservation() throws {
        let (root, asset) = try store(Data([1, 2, 3]))
        let otherAccount = directory.appendingPathComponent("otherAccount")
        try FileManager.default.createDirectory(at: otherAccount, withIntermediateDirectories: true)
        let otherRoot = SpaceGramMediaArchive.root(mediaBoxPath: otherAccount.appendingPathComponent("media").path)
        let isolated = try waitForCallback("other account") {
            SpaceGramMediaArchive.list(root: otherRoot, ids: [asset.id], completion: $0)
        }
        XCTAssertTrue(isolated.isEmpty)
        let metadata = root.appendingPathComponent(asset.id + ".json")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: metadata)) as? [String: Any])
        object["version"] = 2
        let future = try JSONSerialization.data(withJSONObject: object)
        try future.write(to: metadata)
        let preserved = try waitForCallback("newer schema") {
            SpaceGramMediaArchive.list(root: root, ids: [asset.id], completion: $0)
        }
        XCTAssertTrue(preserved.isEmpty)
        XCTAssertEqual(try? Data(contentsOf: metadata), future)
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
        let configured = try waitForCallback("policy") {
            SpaceGramMediaArchive.setPolicy(root: root, policy: policy, completion: $0)
        }
        XCTAssertTrue(configured)
        let metadata = root.appendingPathComponent(asset.id + ".json")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: metadata)) as? [String: Any])
        object["timestamp"] = Date().timeIntervalSince1970 - 8 * 24 * 60 * 60
        try JSONSerialization.data(withJSONObject: object).write(to: metadata)
        let retained = try waitForCallback("automatic cleanup disabled") {
            SpaceGramMediaArchive.list(root: root, ids: [asset.id], completion: $0)
        }
        XCTAssertEqual(retained.count, 1)
        let cleaned = try waitForCallback("manual cleanup") {
            SpaceGramMediaArchive.cleanExpired(root: root, referencedIds: [asset.id], referencesComplete: true, completion: $0)
        }
        XCTAssertTrue(cleaned)
        XCTAssertFalse(FileManager.default.fileExists(atPath: metadata.path))
    }

    func testOrphanCleanupAndMissingOrCorruptStates() throws {
        let (root, asset) = try store(Data([1, 2, 3]))
        let metadata = root.appendingPathComponent(asset.id + ".json")
        let payload = root.appendingPathComponent(asset.id + ".data.bin")
        try FileManager.default.removeItem(at: payload)
        let missing = try waitForCallback("missing payload") {
            SpaceGramMediaArchive.states(root: root, ids: [asset.id], capturedAt: [:], completion: $0)
        }
        guard case .some(.missing) = missing[asset.id] else { return XCTFail("Missing payload must be visible") }
        try Data([1, 2, 3]).write(to: payload)
        try Data("invalid".utf8).write(to: metadata)
        let corrupt = try waitForCallback("corrupt manifest") {
            SpaceGramMediaArchive.states(root: root, ids: [asset.id], capturedAt: [:], completion: $0)
        }
        guard case .some(.corrupt) = corrupt[asset.id] else { return XCTFail("Corrupt manifest must be visible") }

        let (orphanRoot, orphan) = try store(Data([4, 5, 6]))
        let orphanMetadata = orphanRoot.appendingPathComponent(orphan.id + ".json")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: orphanMetadata)) as? [String: Any])
        object["timestamp"] = Date().timeIntervalSince1970 - 10 * 60
        try JSONSerialization.data(withJSONObject: object).write(to: orphanMetadata)
        SpaceGramMediaArchive.reconcile(root: orphanRoot, referencedIds: [], referencesComplete: true)
        let result = try waitForCallback("reconciled") {
            SpaceGramMediaArchive.usage(root: orphanRoot, completion: $0)
        }
        let usage = try result.get()
        XCTAssertEqual(usage.assetCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphanMetadata.path))
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
        let result = try waitForCallback("isolated usage") {
            SpaceGramMediaArchive.usage(root: secondRoot, completion: $0)
        }
        let usage = try result.get()
        XCTAssertEqual(usage.bytes, 0)
        XCTAssertEqual(usage.assetCount, 0)
        let cleared = try waitForCallback("isolated cleanup") {
            SpaceGramMediaArchive.clear(root: secondRoot, completion: $0)
        }
        XCTAssertTrue(cleared)
        XCTAssertTrue(FileManager.default.fileExists(atPath: firstRoot.appendingPathComponent(firstAsset.id + ".json").path))
    }
}
