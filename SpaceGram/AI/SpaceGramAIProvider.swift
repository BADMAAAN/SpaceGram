import Foundation

public protocol SpaceGramAIProvider {
    func generateText(
        model: String,
        messages: [SpaceGramAIMessage],
        completion: @escaping (Result<String, SpaceGramAIError>) -> Void
    )
}

public protocol SpaceGramAIStreamingTask {
    func cancel()
}

public protocol SpaceGramAIStreamingProvider {
    @discardableResult
    func streamText(
        model: String,
        messages: [SpaceGramAIMessage],
        onUpdate: @escaping (String) -> Void,
        completion: @escaping (Result<Void, SpaceGramAIError>) -> Void
    ) -> SpaceGramAIStreamingTask?
}
