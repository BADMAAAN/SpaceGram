import Foundation

public enum SpaceGramMessageAction: String, CaseIterable {
    case messageShot
    case saveProtectedMedia
    case forwardAsNew
    case forwardWithoutName

    public var titleKey: String {
        switch self {
        case .messageShot:
            return "SpaceGram.MessageMenu.MessageShot"
        case .saveProtectedMedia:
            return "SpaceGram.MessageMenu.SaveProtectedMedia"
        case .forwardAsNew:
            return "SpaceGram.MessageMenu.ForwardAsNew"
        case .forwardWithoutName:
            return "SpaceGram.MessageMenu.ForwardWithoutName"
        }
    }

    public var symbolName: String {
        switch self {
        case .messageShot:
            return "camera.viewfinder"
        case .saveProtectedMedia:
            return "square.and.arrow.down"
        case .forwardAsNew:
            return "plus.message"
        case .forwardWithoutName:
            return "arrowshape.turn.up.right"
        }
    }

    public var isImplemented: Bool {
        switch self {
        case .messageShot, .saveProtectedMedia, .forwardWithoutName:
            return true
        case .forwardAsNew:
            return false
        }
    }

    fileprivate var preferenceKey: String {
        return "spacegram.settings.messageAction.\(self.rawValue)"
    }
}

public struct SpaceGramMessageActionContext {
    public let hasMessages: Bool
    public let hasRenderableContent: Bool
    public let hasAvailableProtectedMedia: Bool
    public let canForward: Bool

    public init(hasMessages: Bool, hasRenderableContent: Bool, hasAvailableProtectedMedia: Bool, canForward: Bool) {
        self.hasMessages = hasMessages
        self.hasRenderableContent = hasRenderableContent
        self.hasAvailableProtectedMedia = hasAvailableProtectedMedia
        self.canForward = canForward
    }
}

public extension SpaceGramMessageAction {
    func isApplicable(to context: SpaceGramMessageActionContext) -> Bool {
        guard self.isImplemented else {
            return false
        }
        switch self {
        case .messageShot:
            return context.hasMessages && context.hasRenderableContent
        case .saveProtectedMedia:
            return context.hasAvailableProtectedMedia
        case .forwardWithoutName:
            return context.canForward
        case .forwardAsNew:
            return false
        }
    }
}

public extension SpaceGramSettings {
    func isMessageActionEnabled(_ action: SpaceGramMessageAction) -> Bool {
        // Every SpaceGram-added long-press action is opt-in. The absence of a
        // persisted value is deliberately false, including after migration.
        return UserDefaults.standard.object(forKey: action.preferenceKey) != nil && UserDefaults.standard.bool(forKey: action.preferenceKey)
    }

    func setMessageActionEnabled(_ action: SpaceGramMessageAction, enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: action.preferenceKey)
    }
}
