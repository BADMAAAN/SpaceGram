import Foundation
import Security

public enum QwengramAIKeychainError: Error, Equatable {
    case invalidKey
    case operationFailed(OSStatus)
}

public enum QwengramAIKeychain {
    private static let service = "com.qwengram.ai"
    private static let qwenAPIKeyAccount = "qwen.api-key"

    public static func saveQwenAPIKey(_ key: String, accountId: Int64) throws {
        guard !key.isEmpty else {
            throw QwengramAIKeychainError.invalidKey
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
                throw QwengramAIKeychainError.operationFailed(addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw QwengramAIKeychainError.operationFailed(updateStatus)
        }
    }

    public static func loadQwenAPIKey(accountId: Int64) throws -> String? {
        if let value = try load(account: scopedAccount(accountId: accountId)) {
            return value
        }
        // One-time migration from the pre-account checkpoint. The first account
        // that opens AI settings claims the old device-local key.
        if let legacy = try load(account: qwenAPIKeyAccount) {
            try saveQwenAPIKey(legacy, accountId: accountId)
            try delete(account: qwenAPIKeyAccount)
            return legacy
        }
        return nil
    }

    public static func deleteQwenAPIKey(accountId: Int64) throws {
        try delete(account: scopedAccount(accountId: accountId))
        // A user may clear data before any screen has triggered migration.
        // Remove the legacy unscoped entry so it cannot reappear on next load.
        try delete(account: qwenAPIKeyAccount)
    }

    private static func load(account: String) throws -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data, let key = String(data: data, encoding: .utf8) else {
            throw QwengramAIKeychainError.operationFailed(status)
        }
        return key
    }

    private static func delete(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw QwengramAIKeychainError.operationFailed(status)
        }
    }

    private static func scopedAccount(accountId: Int64) -> String {
        return qwenAPIKeyAccount + "." + String(accountId)
    }

    private static func baseQuery(account: String) -> [String: Any] {
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
