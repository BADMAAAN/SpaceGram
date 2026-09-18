import Foundation
import QwengramSettings

public final class QwengramQwenProvider: NSObject, QwengramAIProvider, QwengramAIStreamingProvider {
    // Alibaba Cloud Model Studio's documented OpenAI-compatible endpoint.
    public static let defaultEndpoint = URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions")!
    public static let defaultModel = "qwen-plus"

    private let apiKey: String
    private let endpoint: URL
    private let session: URLSession

    public init(apiKey: String, endpoint: URL = QwengramQwenProvider.defaultEndpoint, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.endpoint = endpoint
        self.session = session
    }

    public func generateText(model: String, messages: [QwengramAIMessage], completion: @escaping (Result<String, QwengramAIError>) -> Void) {
        guard QwengramSettings.shared.qwengramEnabled else {
            completion(.failure(.disabled))
            return
        }
        guard !apiKey.isEmpty, !model.isEmpty, !messages.isEmpty else {
            completion(.failure(.invalidRequest))
            return
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30.0
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try JSONEncoder().encode(Request(model: model, messages: messages))
        } catch {
            completion(.failure(.invalidRequest))
            return
        }
        let gate = QwengramAIRequestGate()
        let task = session.dataTask(with: request) { data, response, error in
            defer { gate.finish() }
            guard !gate.wasDisabled else {
                completion(.failure(.disabled))
                return
            }
            if let error {
                completion(.failure(.network(error.localizedDescription)))
                return
            }
            guard let response = response as? HTTPURLResponse else {
                completion(.failure(.network("Missing HTTP response")))
                return
            }
            guard (200 ... 299).contains(response.statusCode) else {
                completion(.failure(.httpStatus(response.statusCode)))
                return
            }
            guard let data else {
                completion(.failure(.emptyResponse))
                return
            }
            do {
                let decoded = try JSONDecoder().decode(Response.self, from: data)
                guard let text = decoded.choices.first?.message.content, !text.isEmpty else {
                    completion(.failure(.emptyResponse))
                    return
                }
                completion(.success(text))
            } catch {
                completion(.failure(.decoding))
            }
        }
        gate.start(task)
    }

    @discardableResult
    public func streamText(model: String, messages: [QwengramAIMessage], onUpdate: @escaping (String) -> Void, completion: @escaping (Result<Void, QwengramAIError>) -> Void) -> QwengramAIStreamingTask? {
        guard QwengramSettings.shared.qwengramEnabled else {
            completion(.failure(.disabled))
            return nil
        }
        guard !apiKey.isEmpty, !model.isEmpty, !messages.isEmpty else {
            completion(.failure(.invalidRequest))
            return nil
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 300.0
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        do {
            request.httpBody = try JSONEncoder().encode(StreamingRequest(model: model, messages: messages, stream: true))
        } catch {
            completion(.failure(.invalidRequest))
            return nil
        }

        let delegate = StreamDelegate(onUpdate: onUpdate, completion: completion)
        let streamSession = URLSession(configuration: session.configuration, delegate: delegate, delegateQueue: nil)
        let task = streamSession.dataTask(with: request)
        delegate.setUp(task: task, session: streamSession)
        return delegate
    }

    private struct Request: Encodable {
        let model: String
        let messages: [QwengramAIMessage]
    }

    private struct StreamingRequest: Encodable {
        let model: String
        let messages: [QwengramAIMessage]
        let stream: Bool
    }

    private struct Response: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable {
                let content: String?
            }
            let message: Message
        }
        let choices: [Choice]
    }
}

private final class StreamDelegate: NSObject, URLSessionDataDelegate, QwengramAIStreamingTask {
    private let onUpdate: (String) -> Void
    private let completion: (Result<Void, QwengramAIError>) -> Void
    private let stateQueue = DispatchQueue(label: "Qwengram.StreamDelegate")
    private let stateQueueKey = DispatchSpecificKey<Void>()
    private var pendingData = Data()
    private var eventData: [String] = []
    private var completed = false
    private var task: URLSessionDataTask?
    private var session: URLSession?
    private var gate: QwengramAIRequestGate?

    init(onUpdate: @escaping (String) -> Void, completion: @escaping (Result<Void, QwengramAIError>) -> Void) {
        self.onUpdate = onUpdate
        self.completion = completion
        super.init()
        self.stateQueue.setSpecific(key: self.stateQueueKey, value: ())
    }

    func setUp(task: URLSessionDataTask, session: URLSession) {
        self.stateQueue.sync {
            self.task = task
            self.session = session
            let gate = QwengramAIRequestGate()
            self.gate = gate
            gate.start(task)
        }
    }

    func cancel() {
        self.withState {
            self.finish(.failure(.network("Request cancelled")))
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        self.stateQueue.async {
            guard !self.completed else {
                completionHandler(.cancel)
                return
            }
            guard let response = response as? HTTPURLResponse else {
                completionHandler(.cancel)
                self.finish(.failure(.network("Missing HTTP response")))
                return
            }
            guard (200 ... 299).contains(response.statusCode) else {
                completionHandler(.cancel)
                self.finish(.failure(.httpStatus(response.statusCode)))
                return
            }
            completionHandler(.allow)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        self.stateQueue.async {
            guard !self.completed else {
                return
            }
            guard self.gate?.wasDisabled != true else {
                self.finish(.failure(.disabled))
                return
            }
            self.pendingData.append(data)
            while let newline = self.pendingData.firstIndex(of: 10) {
                let lineData = self.pendingData.prefix(upTo: newline)
                self.pendingData.removeSubrange(...newline)
                guard var line = String(data: lineData, encoding: .utf8) else {
                    self.finish(.failure(.decoding))
                    return
                }
                if line.last == "\r" {
                    line.removeLast()
                }
                self.process(line: line)
                if self.completed {
                    return
                }
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        self.stateQueue.async {
            guard !self.completed else {
                return
            }
            if let error {
                self.finish(.failure(.network(error.localizedDescription)))
            } else {
                self.finish(.failure(.streamEndedUnexpectedly))
            }
        }
    }

    private func process(line: String) {
        if line.isEmpty {
            processEvent()
        } else if line.hasPrefix("data:") {
            eventData.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
        }
    }

    private func processEvent() {
        guard !eventData.isEmpty else {
            return
        }
        let payload = eventData.joined(separator: "\n")
        eventData.removeAll(keepingCapacity: true)
        if payload == "[DONE]" {
            finish(.success(()))
            return
        }
        do {
            let chunk = try JSONDecoder().decode(StreamChunk.self, from: Data(payload.utf8))
            for choice in chunk.choices {
                if let content = choice.delta.content, !content.isEmpty {
                    onUpdate(content)
                }
            }
        } catch {
            finish(.failure(.decoding))
        }
    }

    private func finish(_ result: Result<Void, QwengramAIError>) {
        guard !completed else {
            return
        }
        completed = true
        let task = self.task
        let session = self.session
        let result: Result<Void, QwengramAIError> = self.gate?.wasDisabled == true ? .failure(.disabled) : result
        self.gate?.finish()
        self.gate = nil
        self.task = nil
        self.session = nil
        self.pendingData.removeAll(keepingCapacity: false)
        self.eventData.removeAll(keepingCapacity: false)
        task?.cancel()
        session?.invalidateAndCancel()
        completion(result)
    }

    private func withState(_ f: () -> Void) {
        if DispatchQueue.getSpecific(key: self.stateQueueKey) != nil {
            f()
        } else {
            self.stateQueue.sync(execute: f)
        }
    }

    private struct StreamChunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable {
                let content: String?
            }
            let delta: Delta
        }
        let choices: [Choice]
    }
}
