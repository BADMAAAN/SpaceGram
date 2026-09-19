import CryptoKit
import Darwin
import Foundation

public struct QwengramArchivedAsset: Codable {
    public let version: Int
    public let id: String
    public let fileName: String
    public let fileExtension: String
    public let kind: String
    public let bytes: Int64
    public let timestamp: Double
    public let sha256: String
}

public enum QwengramMediaArchiveError: Error {
    case unavailable
    case invalidData
    case capacity
    case storage
}

public enum QwengramArchivedAssetState {
    case available(QwengramArchivedAsset)
    case expired
    case missing
    case corrupt
}

// A regular, complete cache inode pinned before Telegram unlinks it. No payload
// is read on Postbox's queue. Closing also releases the bounded pending reservation.
public final class QwengramMediaCapture {
    fileprivate let file: FileHandle
    fileprivate let size: Int64
    fileprivate let modified: timespec
    fileprivate let name: String
    fileprivate let kind: String
    fileprivate let ext: String

    fileprivate init(fd: Int32, info: stat, name: String, kind: String, ext: String) {
        self.file = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        self.size = Int64(info.st_size)
        self.modified = info.st_mtimespec
        self.name = String(name.prefix(256))
        self.kind = kind
        self.ext = ext
    }

    deinit {
        QwengramMediaArchive.releaseCapture(size: self.size)
    }
}

public final class QwengramMediaPreview {
    public let url: URL
    fileprivate init(url: URL) { self.url = url }
    deinit {
        let directory = url.deletingLastPathComponent()
        QwengramMediaArchive.queue.async {
            try? FileManager.default.removeItem(at: directory)
            QwengramMediaArchive.activePreviews -= 1
            QwengramMediaArchive.activePreviewPaths.remove(directory.path)
        }
    }
}

public enum QwengramMediaArchive {
    public static let maxBytes: Int64 = 512 * 1024 * 1024
    public static let maxAssetBytes: Int64 = 128 * 1024 * 1024
    public static let maxAssets = 1000
    public static let retention: TimeInterval = 30 * 24 * 60 * 60
    fileprivate static let queue = DispatchQueue(label: "Qwengram.MediaArchive", qos: .utility)
    fileprivate static var activePreviews = 0
    fileprivate static var activePreviewPaths = Set<String>()
    private static let pendingLock = NSLock()
    private static var pendingCount = 0
    private static var pendingBytes: Int64 = 0
    private struct VersionHeader: Decodable { let version: Int }

    public static func usage(root: URL, completion: @escaping (Result<QwengramMediaArchiveUsage, QwengramMediaArchiveError>) -> Void) {
        queue.async {
            do {
                let usage = try withLock(root: root) { () -> QwengramMediaArchiveUsage in
                    let policy = try readPolicy(root: root)
                    let assets = try maintain(root: root, policy: policy)
                    return QwengramMediaArchiveUsage(bytes: assets.reduce(0) { $0 + $1.bytes }, assetCount: assets.count, policy: policy)
                }
                completion(.success(usage))
            } catch { completion(.failure(.storage)) }
        }
    }

    public static func setPolicy(root: URL, policy: QwengramMediaArchivePolicy, completion: @escaping (Bool) -> Void) {
        queue.async {
            do {
                guard policy.isValid else { throw QwengramMediaArchiveError.invalidData }
                try withLock(root: root) {
                    let file = root.appendingPathComponent("policy.json")
                    try JSONEncoder().encode(policy).write(to: file, options: .atomic)
                    try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: file.path)
                    _ = try maintain(root: root, policy: policy)
                }
                completion(true)
            } catch { completion(false) }
        }
    }

    public static func cleanExpired(root: URL, referencedIds: Set<String>, referencesComplete: Bool, completion: @escaping (Bool) -> Void) {
        queue.async {
            do {
                try withLock(root: root) {
                    let policy = try readPolicy(root: root)
                    let assets = try maintain(root: root, policy: policy, forceExpiry: true)
                    if referencesComplete {
                        let grace = Date().timeIntervalSince1970 - 5 * 60
                        for asset in assets where !referencedIds.contains(asset.id) && asset.timestamp < grace {
                            try erase(root: root, asset: asset)
                        }
                    }
                }
                completion(true)
            } catch { completion(false) }
        }
    }

    public static func reconcile(root: URL, referencedIds: Set<String>, referencesComplete: Bool) {
        guard referencesComplete else { return }
        queue.async {
            do {
                try withLock(root: root) {
                    let policy = try readPolicy(root: root)
                    guard policy.automaticCleanup else { return }
                    let grace = Date().timeIntervalSince1970 - 5 * 60
                    for asset in try maintain(root: root, policy: policy) where !referencedIds.contains(asset.id) && asset.timestamp < grace {
                        try erase(root: root, asset: asset)
                    }
                }
            } catch { NSLog("QwengramMediaArchive: orphan reconciliation failed") }
        }
    }

    // MediaBox belongs to one account's Postbox. This sibling is outside MediaBox
    // cleanup, and disappears with the containing account on account removal.
    public static func root(mediaBoxPath: String) -> URL {
        return URL(fileURLWithPath: mediaBoxPath).deletingLastPathComponent().appendingPathComponent("qwengram-media-v1", isDirectory: true)
    }

    public static func pinCompletedFile(path: String, fileName: String, kind: String, fileExtension: String) -> QwengramMediaCapture? {
        guard !Thread.isMainThread else { return nil }
        let fd = Darwin.open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard fd >= 0 else { return nil }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFREG),
              info.st_size > 0, info.st_size <= maxAssetBytes else {
            _ = Darwin.close(fd)
            return nil
        }
        pendingLock.lock()
        let allowed = pendingCount < 64 && pendingBytes <= maxBytes - Int64(info.st_size)
        if allowed {
            pendingCount += 1
            pendingBytes += Int64(info.st_size)
        }
        pendingLock.unlock()
        guard allowed else {
            _ = Darwin.close(fd)
            return nil
        }
        let ext = fileExtension.lowercased()
        let safeExtension = !ext.isEmpty && ext.count <= 12 && ext.utf8.allSatisfy { (48 ... 57).contains($0) || (97 ... 122).contains($0) } ? ext : "bin"
        return QwengramMediaCapture(fd: fd, info: info, name: fileName, kind: kind, ext: safeExtension)
    }

    fileprivate static func releaseCapture(size: Int64) {
        pendingLock.lock()
        pendingCount -= 1
        pendingBytes -= size
        pendingLock.unlock()
    }

    public static func store(root: URL, captures: [QwengramMediaCapture], completion: @escaping ([QwengramArchivedAsset]) -> Void) {
        queue.async {
            var saved: [QwengramArchivedAsset] = []
            do {
                try withLock(root: root) {
                    let policy = try readPolicy(root: root)
                    var assets = try maintain(root: root, policy: policy)
                    for capture in captures {
                        do {
                            while !assets.isEmpty && (assets.count >= maxAssets || assets.reduce(Int64(0), { $0 + $1.bytes }) > policy.storageLimitBytes - capture.size) {
                                try erase(root: root, asset: assets.removeFirst())
                            }
                            let id = UUID().uuidString.lowercased()
                            let partial = root.appendingPathComponent(id + ".partial")
                            defer { try? FileManager.default.removeItem(at: partial) }
                            let digest = try copyAndHash(from: capture.file, to: partial, size: capture.size)
                            var after = stat()
                            guard fstat(capture.file.fileDescriptor, &after) == 0,
                                  after.st_size == capture.size,
                                  after.st_mtimespec.tv_sec == capture.modified.tv_sec,
                                  after.st_mtimespec.tv_nsec == capture.modified.tv_nsec else { throw QwengramMediaArchiveError.invalidData }
                            let asset = QwengramArchivedAsset(version: 1, id: id, fileName: capture.name, fileExtension: capture.ext, kind: capture.kind, bytes: capture.size, timestamp: Date().timeIntervalSince1970, sha256: digest)
                            let destination = payload(root: root, asset: asset)
                            try FileManager.default.moveItem(at: partial, to: destination)
                            do {
                                try JSONEncoder().encode(asset).write(to: root.appendingPathComponent(id + ".json"), options: .atomic)
                            } catch {
                                try? FileManager.default.removeItem(at: destination)
                                throw error
                            }
                            assets.append(asset)
                            saved.append(asset)
                        } catch {
                            NSLog("QwengramMediaArchive: asset copy failed; Telegram continues")
                        }
                    }
                    let retainedIds = Set(assets.map { $0.id })
                    saved.removeAll { !retainedIds.contains($0.id) }
                }
            } catch {
                NSLog("QwengramMediaArchive: storage unavailable; Telegram continues")
            }
            completion(saved)
        }
    }

    public static func list(root: URL, ids: [String], completion: @escaping ([QwengramArchivedAsset]) -> Void) {
        queue.async {
            let wanted = Set(ids)
            let result = try? withLock(root: root) { try maintain(root: root, policy: readPolicy(root: root)).filter { wanted.contains($0.id) } }
            completion(result ?? [])
        }
    }

    // Lightweight list indicator: inspect manifests and file metadata only.
    // Avoid maintenance here so detail can still diagnose a damaged manifest.
    public static func available(root: URL, ids: [String], completion: @escaping (Set<String>) -> Void) {
        queue.async {
            var available = Set<String>()
            do {
                try withLock(root: root) {
                    let policy = try readPolicy(root: root)
                    let cutoff = policy.automaticCleanup ? Date().timeIntervalSince1970 - Double(policy.retentionDays) * 24 * 60 * 60 : -Double.infinity
                    for id in Set(ids) where UUID(uuidString: id) != nil {
                        let metadata = root.appendingPathComponent(id + ".json")
                        guard let values = try? metadata.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]),
                              values.isRegularFile == true, values.isSymbolicLink != true,
                              (values.fileSize ?? Int.max) <= 8192,
                              let data = try? Data(contentsOf: metadata),
                              let asset = try? JSONDecoder().decode(QwengramArchivedAsset.self, from: data),
                              asset.version == 1, asset.id == id, asset.timestamp.isFinite, asset.timestamp >= cutoff,
                              asset.bytes > 0, asset.bytes <= maxAssetBytes,
                              asset.sha256.count == 64,
                              !asset.fileExtension.isEmpty, asset.fileExtension.count <= 12,
                              asset.fileExtension.utf8.allSatisfy({ (48 ... 57).contains($0) || (97 ... 122).contains($0) }) else { continue }
                        let payloadValues = try? payload(root: root, asset: asset).resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
                        if payloadValues?.isRegularFile == true, payloadValues?.isSymbolicLink != true,
                           Int64(payloadValues?.fileSize ?? -1) == asset.bytes { available.insert(id) }
                    }
                }
            } catch { }
            completion(available)
        }
    }

    // Inspect only explicitly linked assets on the media queue. This does not
    // load binary payloads into memory or erase evidence before reporting it.
    public static func states(root: URL, ids: [String], capturedAt: [String: Int64], completion: @escaping ([String: QwengramArchivedAssetState]) -> Void) {
        queue.async {
            var result: [String: QwengramArchivedAssetState] = [:]
            do {
                try withLock(root: root) {
                    let policy = try readPolicy(root: root)
                    let cutoff = policy.automaticCleanup ? Date().timeIntervalSince1970 - Double(policy.retentionDays) * 24 * 60 * 60 : -Double.infinity
                    for id in Set(ids) where UUID(uuidString: id) != nil {
                        let metadata = root.appendingPathComponent(id + ".json")
                        guard FileManager.default.fileExists(atPath: metadata.path) else {
                            result[id] = Double(capturedAt[id] ?? 0) < cutoff ? .expired : .missing
                            continue
                        }
                        guard let metadataValues = try? metadata.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]),
                              metadataValues.isRegularFile == true, metadataValues.isSymbolicLink != true,
                              (metadataValues.fileSize ?? Int.max) <= 8192,
                              let data = try? Data(contentsOf: metadata),
                              let asset = try? JSONDecoder().decode(QwengramArchivedAsset.self, from: data),
                              asset.version == 1, asset.id == id, asset.bytes > 0, asset.bytes <= maxAssetBytes,
                              !asset.fileExtension.isEmpty, asset.fileExtension.count <= 12,
                              asset.fileExtension.utf8.allSatisfy({ (48 ... 57).contains($0) || (97 ... 122).contains($0) }),
                              asset.sha256.count == 64 else {
                            result[id] = .corrupt
                            continue
                        }
                        if asset.timestamp < cutoff {
                            result[id] = .expired
                            continue
                        }
                        let url = payload(root: root, asset: asset)
                        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]),
                              values.isRegularFile == true, values.isSymbolicLink != true else {
                            result[id] = .missing
                            continue
                        }
                        guard Int64(values.fileSize ?? -1) == asset.bytes,
                              (try? hashFile(url: url, size: asset.bytes)) == asset.sha256 else {
                            result[id] = .corrupt
                            continue
                        }
                        result[id] = .available(asset)
                    }
                }
            } catch {
                for id in ids where result[id] == nil { result[id] = .missing }
            }
            completion(result)
        }
    }

    public static func remove(root: URL, ids: [String]) {
        queue.async {
            do {
                try withLock(root: root) {
                    let wanted = Set(ids)
                    for asset in try maintain(root: root, policy: readPolicy(root: root)) where wanted.contains(asset.id) { try erase(root: root, asset: asset) }
                }
            } catch { NSLog("QwengramMediaArchive: cleanup failed") }
        }
    }

    public static func clear(root: URL, completion: @escaping (Bool) -> Void) {
        queue.async {
            do {
                try withLock(root: root) {
                    for asset in try maintain(root: root, policy: readPolicy(root: root)) { try erase(root: root, asset: asset) }
                }
                completion(true)
            } catch {
                NSLog("QwengramMediaArchive: clear failed")
                completion(false)
            }
        }
    }

    // Quick Look gets a verified private copy, so eviction cannot invalidate an
    // open preview. The lease removes it on dismissal. Never return cache URLs.
    public static func preview(root: URL, id: String, completion: @escaping (Result<QwengramMediaPreview, QwengramMediaArchiveError>) -> Void) {
        queue.async {
            do {
                guard activePreviews < 4 else { throw QwengramMediaArchiveError.capacity }
                let preview = try withLock(root: root) { () -> QwengramMediaPreview in
                    guard let asset = try maintain(root: root, policy: readPolicy(root: root)).first(where: { $0.id == id }) else { throw QwengramMediaArchiveError.unavailable }
                    try maintainPreviews(reserving: asset.bytes)
                    let source = try FileHandle(forReadingFrom: payload(root: root, asset: asset))
                    defer { try? source.close() }
                    let parent = FileManager.default.temporaryDirectory.appendingPathComponent("qwengram-preview-" + UUID().uuidString, isDirectory: true)
                    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
                    let destination = parent.appendingPathComponent("media." + asset.fileExtension)
                    do {
                        guard try copyAndHash(from: source, to: destination, size: asset.bytes) == asset.sha256 else { throw QwengramMediaArchiveError.invalidData }
                    } catch {
                        try? FileManager.default.removeItem(at: parent)
                        throw error
                    }
                    activePreviews += 1
                    activePreviewPaths.insert(parent.path)
                    return QwengramMediaPreview(url: destination)
                }
                completion(.success(preview))
            } catch {
                completion(.failure((error as? QwengramMediaArchiveError) ?? .storage))
            }
        }
    }

    private static func withLock<T>(root: URL, _ body: () throws -> T) throws -> T {
        let fm = FileManager.default
        // Do not resurrect a removed account while a capture is queued.
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: root.deletingLastPathComponent().path, isDirectory: &isDirectory), isDirectory.boolValue else { throw QwengramMediaArchiveError.unavailable }
        try fm.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var root = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try root.setResourceValues(values)
        let fd = Darwin.open(root.appendingPathComponent(".lock").path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, mode_t(S_IRUSR | S_IWUSR))
        guard fd >= 0 else { throw QwengramMediaArchiveError.storage }
        defer { _ = Darwin.close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw QwengramMediaArchiveError.storage }
        defer { _ = flock(fd, LOCK_UN) }
        return try body()
    }

    private static func payload(root: URL, asset: QwengramArchivedAsset) -> URL {
        return root.appendingPathComponent(asset.id + ".data." + asset.fileExtension)
    }

    private static func erase(root: URL, asset: QwengramArchivedAsset) throws {
        let fm = FileManager.default
        let path = payload(root: root, asset: asset)
        if fm.fileExists(atPath: path.path) { try fm.removeItem(at: path) }
        let metadata = root.appendingPathComponent(asset.id + ".json")
        if fm.fileExists(atPath: metadata.path) { try fm.removeItem(at: metadata) }
    }

    private static func readPolicy(root: URL) throws -> QwengramMediaArchivePolicy {
        let file = root.appendingPathComponent("policy.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return .default }
        let values = try file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              (values.fileSize ?? Int.max) <= 8192,
              let policy = try? JSONDecoder().decode(QwengramMediaArchivePolicy.self, from: Data(contentsOf: file)), policy.isValid else {
            throw QwengramMediaArchiveError.invalidData
        }
        return policy
    }

    private static func maintain(root: URL, policy: QwengramMediaArchivePolicy, forceExpiry: Bool = false) throws -> [QwengramArchivedAsset] {
        let fm = FileManager.default
        let files = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        var assets: [QwengramArchivedAsset] = []
        let cutoff = (policy.automaticCleanup || forceExpiry) ? Date().timeIntervalSince1970 - Double(policy.retentionDays) * 24 * 60 * 60 : -Double.infinity
        for file in files where file.pathExtension == "json" && UUID(uuidString: file.deletingPathExtension().lastPathComponent) != nil {
            let info = try file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
            if info.isRegularFile == true, info.isSymbolicLink != true, (info.fileSize ?? Int.max) <= 8192,
               let data = try? Data(contentsOf: file), let header = try? JSONDecoder().decode(VersionHeader.self, from: data), header.version > 1 {
                // An older binary must not destroy a newer manifest schema.
                throw QwengramMediaArchiveError.invalidData
            }
            guard info.isRegularFile == true, info.isSymbolicLink != true, (info.fileSize ?? Int.max) <= 8192,
                  let data = try? Data(contentsOf: file), let asset = try? JSONDecoder().decode(QwengramArchivedAsset.self, from: data),
                  asset.version == 1, UUID(uuidString: asset.id) != nil, asset.id == file.deletingPathExtension().lastPathComponent,
                  !asset.fileExtension.isEmpty, asset.fileExtension.count <= 12,
                  asset.fileExtension.utf8.allSatisfy({ (48 ... 57).contains($0) || (97 ... 122).contains($0) }),
                  asset.bytes > 0, asset.bytes <= maxAssetBytes, asset.timestamp.isFinite, asset.timestamp >= cutoff,
                  asset.sha256.count == 64 else { continue }
            let payloadInfo = try? payload(root: root, asset: asset).resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
            guard payloadInfo?.isRegularFile == true, payloadInfo?.isSymbolicLink != true, Int64(payloadInfo?.fileSize ?? -1) == asset.bytes else { continue }
            assets.append(asset)
        }
        assets = retainedAssets(assets, storageLimitBytes: policy.storageLimitBytes)
        var retained = Set([".lock", "policy.json"])
        for asset in assets {
            retained.insert(asset.id + ".json")
            retained.insert(asset.id + ".data." + asset.fileExtension)
        }
        // Commit metadata is written last; interrupted copies and orphan payloads
        // are safely reclaimed under the same cross-process lock.
        for file in files where !retained.contains(file.lastPathComponent) { try fm.removeItem(at: file) }
        return assets
    }

    public static func retainedAssets(_ candidates: [QwengramArchivedAsset], storageLimitBytes: Int64, maxCount: Int = QwengramMediaArchive.maxAssets) -> [QwengramArchivedAsset] {
        var assets = candidates.sorted { $0.timestamp < $1.timestamp }
        var total = assets.reduce(Int64(0)) { $0 + $1.bytes }
        while !assets.isEmpty && (assets.count > maxCount || total > storageLimitBytes) {
            total -= assets.removeFirst().bytes
        }
        return assets
    }

    private static func maintainPreviews(reserving bytes: Int64) throws {
        let fm = FileManager.default
        let folders = try fm.contentsOfDirectory(at: fm.temporaryDirectory, includingPropertiesForKeys: [.creationDateKey])
        var total: Int64 = 0
        for folder in folders where folder.lastPathComponent.hasPrefix("qwengram-preview-") {
            let date = try folder.resourceValues(forKeys: [.creationDateKey]).creationDate ?? .distantPast
            // Crashed processes cannot run lease deinit. Expire their temporary
            // previews too, and refuse more space while the preview cap is full.
            if Date().timeIntervalSince(date) > 24 * 60 * 60 && !activePreviewPaths.contains(folder.path) {
                try fm.removeItem(at: folder)
            } else {
                for file in try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey]) {
                    total += Int64(try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
                }
            }
        }
        guard total <= maxBytes - bytes else { throw QwengramMediaArchiveError.capacity }
    }

    private static func copyAndHash(from input: FileHandle, to destination: URL, size: Int64) throws -> String {
        guard FileManager.default.createFile(atPath: destination.path, contents: nil, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]) else { throw QwengramMediaArchiveError.storage }
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        var hash = SHA256()
        var remaining = size
        while remaining > 0 {
            guard let data = try input.read(upToCount: Int(min(remaining, 1024 * 1024))), !data.isEmpty else { throw QwengramMediaArchiveError.invalidData }
            try output.write(contentsOf: data)
            hash.update(data: data)
            remaining -= Int64(data.count)
        }
        guard (try input.read(upToCount: 1) ?? Data()).isEmpty else { throw QwengramMediaArchiveError.invalidData }
        try output.synchronize()
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func hashFile(url: URL, size: Int64) throws -> String {
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        var hash = SHA256()
        var remaining = size
        while remaining > 0 {
            guard let data = try input.read(upToCount: Int(min(remaining, 1024 * 1024))), !data.isEmpty else { throw QwengramMediaArchiveError.invalidData }
            hash.update(data: data)
            remaining -= Int64(data.count)
        }
        guard (try input.read(upToCount: 1) ?? Data()).isEmpty else { throw QwengramMediaArchiveError.invalidData }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
