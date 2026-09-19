public enum SpaceGramBotCategory: CaseIterable, Equatable {
    case ai
    case media
    case utilities
    case custom

    public static let allCases: [SpaceGramBotCategory] = [.ai, .media, .utilities, .custom]
}

public struct SpaceGramBotDescriptor {
    public let id: String
    public let title: String
    public let subtitle: String
    public let username: String?
    public let category: SpaceGramBotCategory
    public let isEnabled: Bool

    public init(id: String, title: String, subtitle: String, username: String?, category: SpaceGramBotCategory, isEnabled: Bool) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.username = username
        self.category = category
        self.isEnabled = isEnabled
    }
}

public enum SpaceGramBotCatalog {
    public static let defaultBots: [SpaceGramBotDescriptor] = [
        SpaceGramBotDescriptor(id: "qwen-assistant", title: "Qwen Assistant", subtitle: "Ask Qwen", username: nil, category: .ai, isEnabled: true),
        SpaceGramBotDescriptor(id: "summarizer", title: "Summarizer", subtitle: "Summarize text", username: nil, category: .ai, isEnabled: true),
        SpaceGramBotDescriptor(id: "translator", title: "Translator", subtitle: "Translate text", username: nil, category: .ai, isEnabled: true),
        SpaceGramBotDescriptor(id: "media-tools", title: "Media Tools", subtitle: "Coming soon", username: nil, category: .media, isEnabled: false),
        SpaceGramBotDescriptor(id: "qr-tools", title: "QR Tools", subtitle: "Generate QR codes", username: nil, category: .utilities, isEnabled: true),
        SpaceGramBotDescriptor(id: "reminders", title: "Reminders", subtitle: "Coming soon", username: nil, category: .utilities, isEnabled: false),
        SpaceGramBotDescriptor(id: "add-bot", title: "Add Bot", subtitle: "Coming soon", username: nil, category: .custom, isEnabled: false),
    ]
}
