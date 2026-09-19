import Foundation

public struct QwengramPrivacyPolicy: Codable, Equatable {
    public static let currentVersion = 1
    public static let `default` = QwengramPrivacyPolicy()

    public let version: Int
    public var hideNotificationSender: Bool
    public var hideNotificationPreview: Bool
    public var useGenericNotificationText: Bool
    public var hideNotificationChatTitle: Bool
    public var notificationPrivacyWhenAppLocked: Bool
    public var stripPhotoMetadata: Bool

    public init(
        hideNotificationSender: Bool = false,
        hideNotificationPreview: Bool = false,
        useGenericNotificationText: Bool = false,
        hideNotificationChatTitle: Bool = false,
        notificationPrivacyWhenAppLocked: Bool = false,
        stripPhotoMetadata: Bool = false
    ) {
        self.version = Self.currentVersion
        self.hideNotificationSender = hideNotificationSender
        self.hideNotificationPreview = hideNotificationPreview
        self.useGenericNotificationText = useGenericNotificationText
        self.hideNotificationChatTitle = hideNotificationChatTitle
        self.notificationPrivacyWhenAppLocked = notificationPrivacyWhenAppLocked
        self.stripPhotoMetadata = stripPhotoMetadata
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case hideNotificationSender
        case hideNotificationPreview
        case useGenericNotificationText
        case hideNotificationChatTitle
        case notificationPrivacyWhenAppLocked
        case stripPhotoMetadata
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let version = try values.decode(Int.self, forKey: .version)
        guard version == Self.currentVersion else {
            throw QwengramPrivacyPolicyError.unsupportedVersion
        }
        self.version = version
        self.hideNotificationSender = try values.decodeIfPresent(Bool.self, forKey: .hideNotificationSender) ?? false
        self.hideNotificationPreview = try values.decodeIfPresent(Bool.self, forKey: .hideNotificationPreview) ?? false
        self.useGenericNotificationText = try values.decodeIfPresent(Bool.self, forKey: .useGenericNotificationText) ?? false
        self.hideNotificationChatTitle = try values.decodeIfPresent(Bool.self, forKey: .hideNotificationChatTitle) ?? false
        self.notificationPrivacyWhenAppLocked = try values.decodeIfPresent(Bool.self, forKey: .notificationPrivacyWhenAppLocked) ?? false
        self.stripPhotoMetadata = try values.decodeIfPresent(Bool.self, forKey: .stripPhotoMetadata) ?? false
    }

    public func notificationPresentation(title: String?, subtitle: String?, body: String?, appLocked: Bool) -> QwengramNotificationPrivacyPresentation {
        let shouldApply = !self.notificationPrivacyWhenAppLocked || appLocked
        guard shouldApply else {
            return QwengramNotificationPrivacyPresentation(title: title, subtitle: subtitle, body: body, allowsRichBody: true, allowsSender: true, allowsAttachments: true)
        }
        let hideIdentity = self.hideNotificationSender || self.hideNotificationChatTitle
        if self.useGenericNotificationText {
            return QwengramNotificationPrivacyPresentation(title: "Qwengram", subtitle: nil, body: "New notification", allowsRichBody: false, allowsSender: false, allowsAttachments: false)
        }
        return QwengramNotificationPrivacyPresentation(
            title: hideIdentity ? "Qwengram" : title,
            subtitle: hideIdentity ? nil : subtitle,
            body: self.hideNotificationPreview ? "New message" : body,
            allowsRichBody: !self.hideNotificationPreview,
            allowsSender: !hideIdentity,
            allowsAttachments: !self.hideNotificationPreview
        )
    }
}

public struct QwengramNotificationPrivacyPresentation: Equatable {
    public let title: String?
    public let subtitle: String?
    public let body: String?
    public let allowsRichBody: Bool
    public let allowsSender: Bool
    public let allowsAttachments: Bool

    public init(title: String?, subtitle: String?, body: String?, allowsRichBody: Bool, allowsSender: Bool, allowsAttachments: Bool) {
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.allowsRichBody = allowsRichBody
        self.allowsSender = allowsSender
        self.allowsAttachments = allowsAttachments
    }
}

public enum QwengramEmergencyAction: String, Codable, Equatable {
    // Groundwork only. No destructive or remote action is implemented.
    case lockApplication
}

public enum QwengramPrivacyPolicyError: Error {
    case unavailable
    case invalidData
    case unsupportedVersion
}

public enum QwengramPrivacyPolicyStore {
    private static let accountFileName = "qwengram-privacy-v1.json"
    private static let notificationKeyPrefix = "qwengram.privacy.notification.v1."

    public static func loadAccountPolicy(mediaBoxPath: String) -> QwengramPrivacyPolicy {
        let url = accountPolicyURL(mediaBoxPath: mediaBoxPath)
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true, values.isSymbolicLink != true,
              (values.fileSize ?? Int.max) <= 16 * 1024,
              let data = try? Data(contentsOf: url),
              let policy = try? JSONDecoder().decode(QwengramPrivacyPolicy.self, from: data) else {
            return .default
        }
        return policy
    }

    @discardableResult
    public static func saveAccountPolicy(_ policy: QwengramPrivacyPolicy, accountId: Int64, mediaBoxPath: String, baseBundleId: String?) -> Bool {
        guard policy.version == QwengramPrivacyPolicy.currentVersion,
              let data = try? JSONEncoder().encode(policy) else {
            return false
        }
        let url = accountPolicyURL(mediaBoxPath: mediaBoxPath)
        do {
            let parent = url.deletingLastPathComponent()
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: parent.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw QwengramPrivacyPolicyError.unavailable
            }
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)
        } catch {
            return false
        }
        if let defaults = notificationDefaults(baseBundleId: baseBundleId) {
            defaults.set(data, forKey: notificationKey(accountId: accountId))
        }
        return true
    }

    public static func loadNotificationPolicy(accountId: Int64, baseBundleId: String) -> QwengramPrivacyPolicy {
        guard let data = notificationDefaults(baseBundleId: baseBundleId)?.data(forKey: notificationKey(accountId: accountId)),
              data.count <= 16 * 1024,
              let policy = try? JSONDecoder().decode(QwengramPrivacyPolicy.self, from: data) else {
            return .default
        }
        return policy
    }

    public static func clearAccountPolicy(accountId: Int64, mediaBoxPath: String, baseBundleId: String?) {
        let url = accountPolicyURL(mediaBoxPath: mediaBoxPath)
        if FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
        }
        notificationDefaults(baseBundleId: baseBundleId)?.removeObject(forKey: notificationKey(accountId: accountId))
    }

    private static func accountPolicyURL(mediaBoxPath: String) -> URL {
        return URL(fileURLWithPath: mediaBoxPath).deletingLastPathComponent().appendingPathComponent(accountFileName)
    }

    private static func notificationDefaults(baseBundleId: String?) -> UserDefaults? {
        guard let baseBundleId, !baseBundleId.isEmpty else { return nil }
        return UserDefaults(suiteName: "group.\(baseBundleId)")
    }

    private static func notificationKey(accountId: Int64) -> String {
        return notificationKeyPrefix + String(accountId)
    }
}
