import Foundation

public struct QwengramAIAttachment: Codable, Equatable {
    public enum Kind: String, Codable {
        case image, document, telegramMessage, archivedMedia, selectedText
    }
    public let kind: Kind
    public let displayName: String?
    public let referenceId: String?

    public init(kind: Kind, displayName: String? = nil, referenceId: String? = nil) {
        self.kind = kind
        self.displayName = displayName
        self.referenceId = referenceId
    }
}

public struct QwengramAIMessage: Codable, Equatable {
    public enum Role: String, Codable {
        case system
        case user
        case assistant
    }

    public let role: Role
    public let content: String
    public let id: String
    public let attachments: [QwengramAIAttachment]

    public init(role: Role, content: String, id: String = UUID().uuidString.lowercased(), attachments: [QwengramAIAttachment] = []) {
        self.role = role
        self.content = content
        self.id = id
        self.attachments = attachments
    }

    private enum CodingKeys: String, CodingKey { case role, content, id, attachments }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.role = try values.decode(Role.self, forKey: .role)
        self.content = try values.decode(String.self, forKey: .content)
        self.id = try values.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString.lowercased()
        self.attachments = try values.decodeIfPresent([QwengramAIAttachment].self, forKey: .attachments) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(role, forKey: .role)
        try values.encode(content, forKey: .content)
        try values.encode(id, forKey: .id)
        if !attachments.isEmpty { try values.encode(attachments, forKey: .attachments) }
    }
}
