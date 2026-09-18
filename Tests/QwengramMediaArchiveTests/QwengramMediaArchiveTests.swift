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
}
