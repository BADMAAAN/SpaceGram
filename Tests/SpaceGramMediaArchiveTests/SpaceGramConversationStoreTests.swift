import Foundation
import SpaceGramAI
import XCTest

private final class SpaceGramConversationTestCallbackValue<Value> {
    private let lock = NSLock()
    private var value: Value?

    func store(_ value: Value) {
        lock.lock()
        self.value = value
        lock.unlock()
    }

    func load() -> Value? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private enum SpaceGramConversationTestError: Error {
    case timedOut(String)
}

final class SpaceGramConversationStoreTests: XCTestCase {
    private func waitForCallback<Value>(_ description: String, _ operation: (@escaping (Value) -> Void) -> Void) throws -> Value {
        let value = SpaceGramConversationTestCallbackValue<Value>()
        let completed = DispatchSemaphore(value: 0)
        operation {
            value.store($0)
            completed.signal()
        }
        guard completed.wait(timeout: .now() + 10.0) == .success else {
            throw SpaceGramConversationTestError.timedOut(description)
        }
        return try XCTUnwrap(value.load(), "Missing callback value for \(description)")
    }

    func testLegacyDirectoryMigrationLoadsHistoryAndClearCannotResurrectIt() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let legacy = directory.appendingPathComponent("qwengram-conversations-v1")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let conversation = SpaceGramAIConversation(title: "Legacy", messages: [SpaceGramAIMessage(role: .user, content: "Saved before upgrade")])
        try JSONEncoder().encode(conversation).write(to: legacy.appendingPathComponent(conversation.id + ".json"))
        let store = SpaceGramConversationStore(mediaBoxPath: directory.appendingPathComponent("media").path)
        let loaded = try waitForCallback("legacy loaded") {
            store.list(completion: $0)
        }
        XCTAssertEqual(try loaded.get(), [conversation])
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
        let cleared = try waitForCallback("cleared") {
            store.clear(completion: $0)
        }
        try cleared.get()
        let restarted = try waitForCallback("restart") {
            SpaceGramConversationStore(mediaBoxPath: directory.appendingPathComponent("media").path).list(completion: $0)
        }
        XCTAssertTrue(try restarted.get().isEmpty)
    }

    func testDeletingBeforeFirstLoadMigratesThenRemovesLegacyConversation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let legacy = directory.appendingPathComponent("qwengram-conversations-v1")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let conversation = SpaceGramAIConversation(title: "Legacy")
        try JSONEncoder().encode(conversation).write(to: legacy.appendingPathComponent(conversation.id + ".json"))
        let store = SpaceGramConversationStore(mediaBoxPath: directory.appendingPathComponent("media").path)
        let removed = try waitForCallback("removed before read") {
            store.remove(id: conversation.id, completion: $0)
        }
        try removed.get()
        let loaded = try waitForCallback("empty") {
            store.list(completion: $0)
        }
        XCTAssertTrue(try loaded.get().isEmpty)
    }

    func testMessageLimitPreservesSystemAndLocalTranscript() {
        let conversation = SpaceGramAIConversation(systemPrompt: "Rule", messages: [
            SpaceGramAIMessage(role: .user, content: "old"),
            SpaceGramAIMessage(role: .assistant, content: "answer"),
            SpaceGramAIMessage(role: .user, content: "recent")
        ])
        let request = SpaceGramConversationStore.requestContext(conversation, messageLimit: 2)
        XCTAssertEqual(request.map { $0.content }, ["Rule", "recent"])
        XCTAssertEqual(conversation.messages.count, 3)
        XCTAssertEqual(SpaceGramConversationStore.requestContext(conversation, messageLimit: 0).map { $0.content }, ["Rule"])
    }

    func testConversationPersistsAcrossStoreInstancesAndCanBeDeleted() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("media").path
        let first = SpaceGramConversationStore(mediaBoxPath: path)
        let message = SpaceGramAIMessage(role: .user, content: "A private question")
        let conversation = SpaceGramAIConversation(title: "Test", model: "qwen-plus", messages: [message])
        let saved = try waitForCallback("saved") {
            first.save(conversation, completion: $0)
        }
        try saved.get()

        let reopened = SpaceGramConversationStore(mediaBoxPath: path)
        let loaded = try waitForCallback("loaded") {
            reopened.list(completion: $0)
        }
        let conversations = try loaded.get()
        XCTAssertEqual(conversations.count, 1)
        XCTAssertEqual(conversations.first?.id, conversation.id)
        XCTAssertEqual(conversations.first?.messages, [message])

        let removed = try waitForCallback("removed") {
            reopened.remove(id: conversation.id, completion: $0)
        }
        try removed.get()
        let empty = try waitForCallback("empty") {
            first.list(completion: $0)
        }
        XCTAssertTrue(try empty.get().isEmpty)
    }

    func testContextRetainsNewestCompleteMessages() {
        let messages = [
            SpaceGramAIMessage(role: .user, content: "old question"),
            SpaceGramAIMessage(role: .assistant, content: "old answer"),
            SpaceGramAIMessage(role: .user, content: "new question")
        ]
        XCTAssertEqual(SpaceGramConversationStore.requestContext(messages, characterBudget: 12), [messages[2]])
        XCTAssertEqual(SpaceGramConversationStore.requestContext(messages, characterBudget: 100), messages)
    }

    func testRenamePartialResponseAndAccountIsolation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let firstAccount = directory.appendingPathComponent("account-one")
        let secondAccount = directory.appendingPathComponent("account-two")
        try FileManager.default.createDirectory(at: firstAccount, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondAccount, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = SpaceGramConversationStore(mediaBoxPath: firstAccount.appendingPathComponent("media").path)
        let second = SpaceGramConversationStore(mediaBoxPath: secondAccount.appendingPathComponent("media").path)
        let created = Date(timeIntervalSince1970: 100)
        let user = SpaceGramAIMessage(role: .user, content: "Question")
        let partial = SpaceGramAIMessage(role: .assistant, content: "Partial answer")
        var conversation = SpaceGramAIConversation(title: "Original", model: "qwen-plus", createdAt: created, messages: [user, partial])
        conversation.title = "Renamed"
        conversation.titleIsCustom = true
        let saved = try waitForCallback("saved") {
            first.save(conversation, completion: $0)
        }
        try saved.get()
        let loaded = try waitForCallback("reloaded") {
            first.list(completion: $0)
        }
        let value = try XCTUnwrap(try loaded.get().first)
        XCTAssertEqual(value.title, "Renamed")
        XCTAssertTrue(value.titleIsCustom)
        XCTAssertEqual(value.createdAt, created)
        XCTAssertEqual(value.messages.last?.content, "Partial answer")
        XCTAssertEqual(value.messages.last?.id, partial.id)
        let isolated = try waitForCallback("isolated") {
            second.list(completion: $0)
        }
        XCTAssertTrue(try isolated.get().isEmpty)
    }

    func testV1ConversationMigrationAndCorruptFileIsolation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = UUID().uuidString.lowercased()
        let root = directory.appendingPathComponent("spacegram-conversations-v1")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fixture = """
        {"version":1,"id":"\(id)","title":"Old title","model":"qwen-plus","updatedAt":100,"messages":[{"role":"user","content":"Old question"}]}
        """
        try Data(fixture.utf8).write(to: root.appendingPathComponent(id + ".json"))
        try Data("broken JSON".utf8).write(to: root.appendingPathComponent(UUID().uuidString.lowercased() + ".json"))
        let store = SpaceGramConversationStore(mediaBoxPath: directory.appendingPathComponent("media").path)
        let loaded = try waitForCallback("migration") {
            store.list(completion: $0)
        }
        let values = try loaded.get()
        XCTAssertEqual(values.count, 1)
        XCTAssertEqual(values[0].version, 2)
        XCTAssertEqual(values[0].title, "Old title")
        XCTAssertEqual(values[0].createdAt, values[0].updatedAt)
        XCTAssertFalse(values[0].titleIsCustom)
        XCTAssertEqual(values[0].messages[0].content, "Old question")
        XCTAssertFalse(values[0].messages[0].id.isEmpty)
    }

    func testContextAlwaysKeepsSystemPromptAndOmitsAttachmentsFromTextBudget() {
        let old = SpaceGramAIMessage(role: .user, content: "Older long question")
        let recent = SpaceGramAIMessage(role: .user, content: "new", attachments: [SpaceGramAIAttachment(kind: .image, displayName: "photo")])
        let conversation = SpaceGramAIConversation(systemPrompt: "Rule", messages: [old, recent])
        let context = SpaceGramConversationStore.requestContext(conversation, characterBudget: 7)
        XCTAssertEqual(context.map { $0.role }, [.system, .user])
        XCTAssertEqual(context.last?.id, recent.id)
        XCTAssertEqual(SpaceGramConversationStore.requestContext(conversation, characterBudget: 3), [])
    }

    func testConversationStorageRejectsOversizedPayload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SpaceGramConversationStore(mediaBoxPath: directory.appendingPathComponent("media").path)
        let oversized = SpaceGramAIConversation(messages: [SpaceGramAIMessage(role: .user, content: String(repeating: "x", count: 1024 * 1024))])
        let rejected = try waitForCallback("size limit") {
            store.save(oversized, completion: $0)
        }
        guard case .failure = rejected else { return XCTFail("Oversized conversation should be rejected") }
    }

    func testClearRemovesOnlySelectedAccountConversations() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let firstAccount = directory.appendingPathComponent("account-one")
        let secondAccount = directory.appendingPathComponent("account-two")
        try FileManager.default.createDirectory(at: firstAccount, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondAccount, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = SpaceGramConversationStore(mediaBoxPath: firstAccount.appendingPathComponent("media").path)
        let second = SpaceGramConversationStore(mediaBoxPath: secondAccount.appendingPathComponent("media").path)
        for (store, title) in [(first, "First"), (second, "Second")] {
            let saved = try waitForCallback("saved \(title)") {
                store.save(SpaceGramAIConversation(title: title), completion: $0)
            }
            try saved.get()
        }

        let cleared = try waitForCallback("cleared") {
            first.clear(completion: $0)
        }
        try cleared.get()

        let firstList = try waitForCallback("first list") {
            first.list(completion: $0)
        }
        XCTAssertTrue(try firstList.get().isEmpty)
        let secondList = try waitForCallback("second list") {
            second.list(completion: $0)
        }
        XCTAssertEqual(try secondList.get().map(\.title), ["Second"])
    }
}
