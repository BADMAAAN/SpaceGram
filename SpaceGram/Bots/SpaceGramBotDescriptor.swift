public enum SpaceGramBotCategory: CaseIterable, Equatable {
    case media
    case utilities
    case custom

    public static let allCases: [SpaceGramBotCategory] = [.media, .utilities, .custom]
}

public struct SpaceGramBotDescriptor {
    public let id: String
    public let titleKey: String
    public let subtitleKey: String
    public let username: String?
    public let category: SpaceGramBotCategory
    public let isEnabled: Bool

    public init(id: String, titleKey: String, subtitleKey: String, username: String?, category: SpaceGramBotCategory, isEnabled: Bool) {
        self.id = id
        self.titleKey = titleKey
        self.subtitleKey = subtitleKey
        self.username = username
        self.category = category
        self.isEnabled = isEnabled
    }
}

public enum SpaceGramBotCatalog {
    public static let defaultBots: [SpaceGramBotDescriptor] = [
        SpaceGramBotDescriptor(id: "translator", titleKey: "SpaceGram.Bot.Translator", subtitleKey: "SpaceGram.Bot.TranslateText", username: nil, category: .utilities, isEnabled: true),
        SpaceGramBotDescriptor(id: "media-tools", titleKey: "SpaceGram.Bot.MediaTools", subtitleKey: "SpaceGram.Soon", username: nil, category: .media, isEnabled: false),
        SpaceGramBotDescriptor(id: "reminders", titleKey: "SpaceGram.Bot.Reminders", subtitleKey: "SpaceGram.Soon", username: nil, category: .utilities, isEnabled: false),
        SpaceGramBotDescriptor(id: "add-bot", titleKey: "SpaceGram.Bot.AddBot", subtitleKey: "SpaceGram.Soon", username: nil, category: .custom, isEnabled: false),
    ]
}
