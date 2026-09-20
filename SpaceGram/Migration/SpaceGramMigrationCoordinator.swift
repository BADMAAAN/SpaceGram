import Darwin
import Foundation

public enum SpaceGramMigrationError: LocalizedError {
    case unavailable
    case conflictingDirectories
    case verificationFailed

    public var errorDescription: String? {
        switch self {
        case .unavailable: return "SpaceGram could not access local migration storage. Unlock the device and retry."
        case .conflictingDirectories: return "Both legacy and SpaceGram archives exist. Both have been preserved. Back up the account data and reconcile these directories before retrying."
        case .verificationFailed: return "SpaceGram could not verify the migrated value. The legacy copy has been preserved; retry after unlocking the device."
        }
    }
}

/// Namespace migration only: payload schemas, UUIDs and account identity stay intact.
public enum SpaceGramMigrationCoordinator {
    public static let version = 2
    private static let defaultsLock = NSRecursiveLock()

    /// Keep legacy preferences as a recovery copy: UserDefaults has no durable
    /// write acknowledgement. The version is diagnostic, never a skip condition.
    @discardableResult
    public static func migrateDefaults(_ defaults: UserDefaults) -> Bool {
        defaultsLock.lock()
        defer { defaultsLock.unlock() }
        var verified = true
        let prefixes = [("qwengram.settings.", "spacegram.settings."), ("Qwengram.", "SpaceGram.")]
        for (key, value) in defaults.dictionaryRepresentation() {
            guard let prefix = prefixes.first(where: { key.hasPrefix($0.0) }) else { continue }
            let destination = prefix.1 + key.dropFirst(prefix.0.count)
            if defaults.object(forKey: destination) == nil {
                defaults.set(value, forKey: destination)
                if let expected = value as? NSObject, let actual = defaults.object(forKey: destination) as? NSObject {
                    verified = expected.isEqual(actual) && verified
                } else {
                    verified = false
                }
            }
        }
        // Version 2 introduces a real Ghost master switch. Preserve an existing
        // installation's effective opt-in without conflating it with SpaceGram's
        // product-wide enabled flag.
        if defaults.object(forKey: "spacegram.settings.ghostModeEnabled") == nil {
            let legacyControls = [
                "spacegram.settings.suppressAutomaticReads",
                "spacegram.settings.hideStoryViews",
                "spacegram.settings.hideOnlinePresence",
                "spacegram.settings.hideChatActivity",
            ]
            defaults.set(legacyControls.contains(where: { defaults.bool(forKey: $0) }), forKey: "spacegram.settings.ghostModeEnabled")
        }
        if verified && defaults.integer(forKey: "spacegram.migration.defaults.version") != version {
            defaults.set(version, forKey: "spacegram.migration.defaults.version")
        }
        return verified
    }

    /// A failed write/read-back never authorizes removal of the only old secret.
    /// Closures also allow failure injection without using the real Keychain.
    public static func migrateSecret(readNew: () throws -> String?, readLegacy: () throws -> String?, writeNew: (String) throws -> Void, removeLegacy: () throws -> Void) throws -> String? {
        if let current = try readNew() { return current }
        guard let legacy = try readLegacy() else { return nil }
        try writeNew(legacy)
        guard try readNew() == legacy else { throw SpaceGramMigrationError.verificationFailed }
        try removeLegacy()
        return legacy
    }

    /// Runs on the caller's storage worker before creating/opening the new root.
    /// A same-parent rename is atomic: restart sees either old or new, never a
    /// partly copied asset/manifest pair. A parent lock serializes app/extensions.
    public static func migrateDirectory(to destination: URL, legacyName: String) throws {
        let parent = destination.deletingLastPathComponent()
        let state = try parent.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard state.isDirectory == true, state.isSymbolicLink != true,
              !legacyName.isEmpty,
              !legacyName.contains("/"), !legacyName.contains("\\"),
              legacyName != ".", legacyName != "..", legacyName != destination.lastPathComponent else {
            throw SpaceGramMigrationError.unavailable
        }
        let lock = parent.appendingPathComponent(".spacegram-migration.lock")
        let descriptor = Darwin.open(lock.path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, mode_t(S_IRUSR | S_IWUSR))
        guard descriptor >= 0 else { throw SpaceGramMigrationError.unavailable }
        defer { _ = close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw SpaceGramMigrationError.unavailable }
        defer { _ = flock(descriptor, LOCK_UN) }
        let legacy = parent.appendingPathComponent(legacyName, isDirectory: true)
        func exists(_ url: URL) throws -> Bool {
            // URL resource values may cache a directory that has since moved or
            // been removed. Recheck the filesystem under the migration lock.
            var info = stat()
            guard lstat(url.path, &info) == 0 else {
                if errno == ENOENT { return false }
                throw SpaceGramMigrationError.unavailable
            }
            // lstat rejects symlinks without following them.
            guard (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) else {
                throw SpaceGramMigrationError.unavailable
            }
            return true
        }
        let hasDestination = try exists(destination)
        guard try exists(legacy) else { return }
        // Never merge divergent archives or silently hide one of them.
        guard !hasDestination else { throw SpaceGramMigrationError.conflictingDirectories }
        guard Darwin.rename(legacy.path, destination.path) == 0 else {
            throw SpaceGramMigrationError.unavailable
        }
    }
}
