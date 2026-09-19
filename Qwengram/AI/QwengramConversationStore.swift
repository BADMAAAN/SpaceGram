import Foundation

public struct QwengramAIConversation: Codable, Equatable {
    public let version: Int
    public let id: String
    public var title: String
    public var titleIsCustom: Bool
    public var model: String
    public let createdAt: Date
    public var updatedAt: Date
    public var systemPrompt: String?
    public var metadata: [String: String]?
    public var messages: [QwengramAIMessage]

    public init(id: String = UUID().uuidString.lowercased(), title: String = "New conversation", titleIsCustom: Bool = false, model: String = "", createdAt: Date = Date(), updatedAt: Date = Date(), systemPrompt: String? = "You are Qwen, a helpful assistant. Be accurate and concise.", metadata: [String: String]? = nil, messages: [QwengramAIMessage] = []) {
        self.version = 2
        self.id = id
        self.title = title
        self.titleIsCustom = titleIsCustom
        self.model = model
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.systemPrompt = systemPrompt
        self.metadata = metadata
        self.messages = messages
    }

    private enum CodingKeys: String, CodingKey { case version, id, title, titleIsCustom, model, createdAt, updatedAt, systemPrompt, metadata, messages }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let storedVersion = try values.decode(Int.self, forKey: .version)
        guard storedVersion == 1 || storedVersion == 2 else { throw QwengramConversationStoreError.invalidData }
        self.version = 2
        self.id = try values.decode(String.self, forKey: .id)
        self.title = try values.decode(String.self, forKey: .title)
        self.titleIsCustom = try values.decodeIfPresent(Bool.self, forKey: .titleIsCustom) ?? false
        self.model = try values.decode(String.self, forKey: .model)
        self.updatedAt = try values.decode(Date.self, forKey: .updatedAt)
        self.createdAt = try values.decodeIfPresent(Date.self, forKey: .createdAt) ?? self.updatedAt
        self.systemPrompt = try values.decodeIfPresent(String.self, forKey: .systemPrompt)
        self.metadata = try values.decodeIfPresent([String: String].self, forKey: .metadata)
        self.messages = try values.decode([QwengramAIMessage].self, forKey: .messages)
    }
}

public enum QwengramConversationStoreError: Error {
    case unavailable
    case invalidData
    case capacity
}

// One protected file per conversation in the selected account directory.
// No credentials or provider requests are persisted here.
public final class QwengramConversationStore {
    public static let maxContextCharacters = 24000
    private static let queue = DispatchQueue(label: "Qwengram.Conversations", qos: .utility)
    private static let maxConversationBytes = 1024 * 1024
    private static let maxConversations = 100
    private let root: URL

    public init(mediaBoxPath: String) {
        self.root = URL(fileURLWithPath: mediaBoxPath).deletingLastPathComponent().appendingPathComponent("qwengram-conversations-v1", isDirectory: true)
    }

    public func list(completion: @escaping (Result<[QwengramAIConversation], Error>) -> Void) {
        Self.queue.async {
            do {
                try self.prepareRoot()
                let files = try FileManager.default.contentsOfDirectory(at: self.root, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
                var result: [QwengramAIConversation] = []
                for file in files where file.pathExtension == "json" && UUID(uuidString: file.deletingPathExtension().lastPathComponent) != nil {
                    guard let values = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey]),
                          values.isRegularFile == true, values.isSymbolicLink != true,
                          (values.fileSize ?? Int.max) <= Self.maxConversationBytes,
                          let conversation = try? JSONDecoder().decode(QwengramAIConversation.self, from: Data(contentsOf: file)),
                          conversation.version == 2,
                          conversation.id == file.deletingPathExtension().lastPathComponent else {
                        NSLog("QwengramConversations: one saved conversation is unreadable")
                        continue
                    }
                    result.append(conversation)
                }
                completion(.success(result.sorted { $0.updatedAt > $1.updatedAt }))
            } catch { completion(.failure(error)) }
        }
    }

    public func save(_ conversation: QwengramAIConversation, completion: @escaping (Result<Void, Error>) -> Void) {
        Self.queue.async {
            do {
                guard conversation.version == 2, UUID(uuidString: conversation.id) != nil else { throw QwengramConversationStoreError.invalidData }
                try self.prepareRoot()
                let file = self.root.appendingPathComponent(conversation.id + ".json")
                if !FileManager.default.fileExists(atPath: file.path) {
                    let count = try FileManager.default.contentsOfDirectory(at: self.root, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }.count
                    guard count < Self.maxConversations else { throw QwengramConversationStoreError.capacity }
                }
                let data = try JSONEncoder().encode(conversation)
                guard data.count <= Self.maxConversationBytes else { throw QwengramConversationStoreError.capacity }
                try data.write(to: file, options: .atomic)
                try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: file.path)
                completion(.success(()))
            } catch { completion(.failure(error)) }
        }
    }

    public func remove(id: String, completion: @escaping (Result<Void, Error>) -> Void) {
        Self.queue.async {
            do {
                guard UUID(uuidString: id) != nil else { throw QwengramConversationStoreError.invalidData }
                let file = self.root.appendingPathComponent(id + ".json")
                if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
                completion(.success(()))
            } catch { completion(.failure(error)) }
        }
    }

    public func clear(completion: @escaping (Result<Void, Error>) -> Void) {
        Self.queue.async {
            do {
                let parent = self.root.deletingLastPathComponent()
                var isDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: parent.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                    throw QwengramConversationStoreError.unavailable
                }
                if FileManager.default.fileExists(atPath: self.root.path) {
                    let state = try self.root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                    guard state.isDirectory == true, state.isSymbolicLink != true else {
                        throw QwengramConversationStoreError.unavailable
                    }
                    try FileManager.default.removeItem(at: self.root)
                }
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }
    }

    // Keep complete messages in chronological order and never split text.
    public static func requestContext(_ messages: [QwengramAIMessage], characterBudget: Int = QwengramConversationStore.maxContextCharacters) -> [QwengramAIMessage] {
        let systemMessages = messages.filter { $0.role == .system }
        let systemCharacters = systemMessages.reduce(0) { $0 + $1.content.count }
        guard systemCharacters <= min(4096, characterBudget) else { return [] }
        var result: [QwengramAIMessage] = []
        var remaining = max(0, characterBudget - systemCharacters)
        for message in messages.reversed() where message.role != .system {
            if message.content.count > remaining { break }
            result.append(message)
            remaining -= message.content.count
        }
        var chronological = Array(result.reversed())
        while chronological.first?.role == .assistant { chronological.removeFirst() }
        return systemMessages + chronological
    }

    public static func requestContext(_ conversation: QwengramAIConversation, characterBudget: Int = QwengramConversationStore.maxContextCharacters) -> [QwengramAIMessage] {
        var messages = conversation.messages
        if let prompt = conversation.systemPrompt, !prompt.isEmpty {
            messages.insert(QwengramAIMessage(role: .system, content: prompt), at: 0)
        }
        return requestContext(messages, characterBudget: characterBudget)
    }

    private func prepareRoot() throws {
        let parent = self.root.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: parent.path, isDirectory: &isDirectory), isDirectory.boolValue else { throw QwengramConversationStoreError.unavailable }
        if FileManager.default.fileExists(atPath: self.root.path) {
            let state = try self.root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard state.isDirectory == true, state.isSymbolicLink != true else { throw QwengramConversationStoreError.unavailable }
        } else {
            try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: false, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        }
        var root = self.root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try root.setResourceValues(values)
    }
}
