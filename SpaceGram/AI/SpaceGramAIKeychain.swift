import Foundation
import Security
import SpaceGramMigration

public enum SpaceGramAIKeychainError: Error, Equatable {
    case invalidKey
    case operationFailed(OSStatus)
}

public enum SpaceGramAIKeychain {
    private static let service = "com.spacegram.ai"
    private static let legacyService = "com.qwengram.ai"
    private static let qwenAPIKeyAccount = "qwen.api-key"
    private static let lock = NSRecursiveLock()

    public static func saveQwenAPIKey(_ key: String, accountId: Int64) throws {
        lock.lock()
        defer { lock.unlock() }
        guard !key.isEmpty else {
            throw SpaceGramAIKeychainError.invalidKey
        }
        let query = baseQuery(account: scopedAccount(accountId: accountId))
        let attributes: [String: Any] = [
            kSecValueData as String: Data(key.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            attributes.forEach { addQuery[$0.key] = $0.value }
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw SpaceGramAIKeychainError.operationFailed(addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw SpaceGramAIKeychainError.operationFailed(updateStatus)
        }
    }

    public static func loadQwenAPIKey(accountId: Int64) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        if let value = try load(account: scopedAccount(accountId: accountId)) {
            return value
        }
        let account = scopedAccount(accountId: accountId)
        if let value = try SpaceGramMigrationCoordinator.migrateSecret(
            readNew: { try load(account: account) },
            readLegacy: { try load(account: account, serviceName: legacyService) },
            writeNew: { try saveQwenAPIKey($0, accountId: accountId) },
            removeLegacy: { try delete(account: account, serviceName: legacyService) }
        ) {
            return value
        }
        // Preserve the historical first-account claim. A durable, add-only
        // owner marker prevents another account claiming the unscoped secret
        // after a crash or a failed legacy deletion. It contains no API key.
        guard try load(account: qwenAPIKeyAccount, serviceName: legacyService) != nil,
              try claimLegacyKey(accountId: accountId) else { return nil }
        return try SpaceGramMigrationCoordinator.migrateSecret(
            readNew: { try load(account: account) },
            readLegacy: { try load(account: qwenAPIKeyAccount, serviceName: legacyService) },
            writeNew: { try saveQwenAPIKey($0, accountId: accountId) },
            removeLegacy: { try delete(account: qwenAPIKeyAccount, serviceName: legacyService) }
        )
    }

    public static func deleteQwenAPIKey(accountId: Int64) throws {
        lock.lock()
        defer { lock.unlock() }
        // A user may clear data before any screen has triggered migration.
        // Remove old entries first so a failed cleanup cannot revive an old key.
        if try claimLegacyKey(accountId: accountId) {
            try delete(account: qwenAPIKeyAccount, serviceName: legacyService)
        }
        try delete(account: scopedAccount(accountId: accountId), serviceName: legacyService)
        try delete(account: scopedAccount(accountId: accountId))
    }

    private static func load(account: String, serviceName: String = SpaceGramAIKeychain.service) throws -> String? {
        var query = baseQuery(account: account, serviceName: serviceName)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data, let key = String(data: data, encoding: .utf8) else {
            throw SpaceGramAIKeychainError.operationFailed(status)
        }
        return key
    }

    private static func delete(account: String, serviceName: String = SpaceGramAIKeychain.service) throws {
        let status = SecItemDelete(baseQuery(account: account, serviceName: serviceName) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SpaceGramAIKeychainError.operationFailed(status)
        }
    }

    private static func scopedAccount(accountId: Int64) -> String {
        return qwenAPIKeyAccount + "." + String(accountId)
    }

    private static func claimLegacyKey(accountId: Int64) throws -> Bool {
        let ownerAccount = "qwen.legacy-owner.v1"
        let owner = String(accountId)
        var query = baseQuery(account: ownerAccount)
        query[kSecValueData as String] = Data(owner.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else {
            throw SpaceGramAIKeychainError.operationFailed(status)
        }
        return try load(account: ownerAccount) == owner
    }

    private static func baseQuery(account: String, serviceName: String = SpaceGramAIKeychain.service) -> [String: Any] {
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: account,
        ]
    }
}
