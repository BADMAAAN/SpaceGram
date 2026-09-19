import Foundation
import SpaceGramMigration
import SpaceGramSettings
import XCTest

final class SpaceGramMigrationTests: XCTestCase {
    private var directory: URL!
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        suite = "SpaceGramTests." + UUID().uuidString
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suite)
        try FileManager.default.removeItem(at: directory)
    }

    func testPreferencesMigrateFalseAndModelWithoutDeletingRecoveryCopy() {
        defaults.set(false, forKey: "qwengram.settings.enabled")
        defaults.set("custom-model", forKey: "qwengram.settings.qwenModel")
        XCTAssertTrue(SpaceGramMigrationCoordinator.migrateDefaults(defaults))
        XCTAssertEqual(defaults.object(forKey: "spacegram.settings.enabled") as? Bool, false)
        XCTAssertEqual(defaults.string(forKey: "spacegram.settings.qwenModel"), "custom-model")
        XCTAssertNotNil(defaults.object(forKey: "qwengram.settings.enabled"))
    }

    func testExtensionMasterGateUsesOnlyProvidedSharedDomain() {
        XCTAssertTrue(SpaceGramSettings.enabledForExtensions(defaults: defaults))
        defaults.set(false, forKey: "spacegram.settings.enabled")
        XCTAssertFalse(SpaceGramSettings.enabledForExtensions(defaults: defaults))
        defaults.set(true, forKey: "spacegram.settings.enabled")
        XCTAssertTrue(SpaceGramSettings.enabledForExtensions(defaults: defaults))
    }

    func testPreferencesNeverOverwriteCurrentValueAndCanRunAgain() {
        defaults.set(true, forKey: "qwengram.settings.enabled")
        defaults.set(false, forKey: "spacegram.settings.enabled")
        XCTAssertTrue(SpaceGramMigrationCoordinator.migrateDefaults(defaults))
        XCTAssertTrue(SpaceGramMigrationCoordinator.migrateDefaults(defaults))
        XCTAssertFalse(defaults.bool(forKey: "spacegram.settings.enabled"))
    }

    func testPartialPreferencesResumeEvenWithVersionMarker() {
        defaults.set(1, forKey: "spacegram.migration.defaults.version")
        defaults.set("old", forKey: "Qwengram.fixture")
        defaults.set(true, forKey: "nagram.fixture")
        XCTAssertTrue(SpaceGramMigrationCoordinator.migrateDefaults(defaults))
        XCTAssertEqual(defaults.string(forKey: "SpaceGram.fixture"), "old")
        XCTAssertNil(defaults.object(forKey: "SpaceGram.fixture.nagram"))
        XCTAssertTrue(defaults.bool(forKey: "nagram.fixture"))
    }

    func testCurrentSecretWinsWithoutLegacyLookup() throws {
        let result = try SpaceGramMigrationCoordinator.migrateSecret(readNew: { "current-fixture" }, readLegacy: { XCTFail("Do not look up old secret"); return nil }, writeNew: { _ in XCTFail("Do not overwrite") }, removeLegacy: { XCTFail("Do not delete") })
        XCTAssertEqual(result, "current-fixture")
    }

    func testSecretReadBackPrecedesLegacyDeletionAndIsIdempotent() throws {
        var current: String?
        var legacy: String? = "fixture-only"
        var writes = 0
        for _ in 0 ..< 2 {
            let value = try SpaceGramMigrationCoordinator.migrateSecret(readNew: { current }, readLegacy: { legacy }, writeNew: { current = $0; writes += 1 }, removeLegacy: { XCTAssertEqual(current, legacy); legacy = nil })
            XCTAssertEqual(value, "fixture-only")
        }
        XCTAssertEqual(writes, 1)
        XCTAssertNil(legacy)
    }

    func testSecretWriteFailureKeepsLegacy() {
        var deleted = false
        XCTAssertThrowsError(try SpaceGramMigrationCoordinator.migrateSecret(readNew: { nil }, readLegacy: { "fixture" }, writeNew: { _ in throw SpaceGramMigrationError.unavailable }, removeLegacy: { deleted = true }))
        XCTAssertFalse(deleted)
    }

    func testSecretReadBackFailureKeepsLegacy() {
        var deleted = false
        XCTAssertThrowsError(try SpaceGramMigrationCoordinator.migrateSecret(readNew: { nil }, readLegacy: { "fixture" }, writeNew: { _ in }, removeLegacy: { deleted = true }))
        XCTAssertFalse(deleted)
    }

    func testSecretLookupFailureDoesNotFallBack() {
        var lookedUp = false
        XCTAssertThrowsError(try SpaceGramMigrationCoordinator.migrateSecret(readNew: { throw SpaceGramMigrationError.unavailable }, readLegacy: { lookedUp = true; return "fixture" }, writeNew: { _ in }, removeLegacy: {}))
        XCTAssertFalse(lookedUp)
    }

    func testSecretDeletionFailureLeavesVerifiedNewCopy() {
        var current: String?
        XCTAssertThrowsError(try SpaceGramMigrationCoordinator.migrateSecret(readNew: { current }, readLegacy: { "fixture" }, writeNew: { current = $0 }, removeLegacy: { throw SpaceGramMigrationError.unavailable }))
        XCTAssertEqual(current, "fixture")
    }

    func testDirectoryMigrationPreservesManifestPayloadAndInterruptedFile() throws {
        let legacy = directory.appendingPathComponent("qwengram-media-v1")
        let destination = directory.appendingPathComponent("spacegram-media-v1")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: false)
        let fixtures = ["asset.json": Data("manifest".utf8), "asset.data.bin": Data([1, 2, 3]), "copy.partial": Data([4])]
        for (name, bytes) in fixtures { try bytes.write(to: legacy.appendingPathComponent(name)) }
        try SpaceGramMigrationCoordinator.migrateDirectory(to: destination, legacyName: legacy.lastPathComponent)
        // Simulate relaunch after the atomic rename and before first store access.
        try SpaceGramMigrationCoordinator.migrateDirectory(to: destination, legacyName: legacy.lastPathComponent)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
        for (name, bytes) in fixtures { XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent(name)), bytes) }
    }

    func testConflictingDirectoriesArePreservedAndRetryable() throws {
        let legacy = directory.appendingPathComponent("old")
        let destination = directory.appendingPathComponent("new")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        let fixture = Data([1, 2])
        try fixture.write(to: legacy.appendingPathComponent("fixture"))
        XCTAssertThrowsError(try SpaceGramMigrationCoordinator.migrateDirectory(to: destination, legacyName: "old"))
        XCTAssertEqual(try Data(contentsOf: legacy.appendingPathComponent("fixture")), fixture)
        // Only the empty test destination is removed; retry must preserve data.
        try FileManager.default.removeItem(at: destination)
        try SpaceGramMigrationCoordinator.migrateDirectory(to: destination, legacyName: "old")
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("fixture")), fixture)
    }

    func testDirectoryMigrationDoesNotTouchAnotherAccount() throws {
        let first = directory.appendingPathComponent("first")
        let second = directory.appendingPathComponent("second")
        for parent in [first, second] {
            try FileManager.default.createDirectory(at: parent.appendingPathComponent("old"), withIntermediateDirectories: true)
            try Data(parent.lastPathComponent.utf8).write(to: parent.appendingPathComponent("old/fixture"))
        }
        try SpaceGramMigrationCoordinator.migrateDirectory(to: first.appendingPathComponent("new"), legacyName: "old")
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.appendingPathComponent("old/fixture").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: second.appendingPathComponent("new").path))
    }

    func testMissingAccountIsNotRecreated() {
        let root = directory.appendingPathComponent("removed/new")
        XCTAssertThrowsError(try SpaceGramMigrationCoordinator.migrateDirectory(to: root, legacyName: "old"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.deletingLastPathComponent().path))
    }

    func testSymlinkRootIsRejectedWithoutMovingTarget() throws {
        let real = directory.appendingPathComponent("real")
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("old"), withDestinationURL: real)
        XCTAssertThrowsError(try SpaceGramMigrationCoordinator.migrateDirectory(to: directory.appendingPathComponent("new"), legacyName: "old"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: real.path))
    }
}
