import Foundation
import SpaceGramAI
import XCTest

final class SpaceGramConversationStoreTests: XCTestCase {
    func testLegacyDirectoryMigrationLoadsHistoryAndClearCannotResurrectIt() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let legacy = directory.appendingPathComponent("qwengram-conversations-v1")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let conversation = SpaceGramAIConversation(title: "Legacy", messages: [SpaceGramAIMessage(role: .user, content: "Saved before upgrade")])
        try JSONEncoder().encode(conversation).write(to: legacy.appendingPathComponent(conversation.id + ".json"))
        let store = SpaceGramConversationStore(mediaBoxPath: directory.appendingPathComponent("media").path)
        let loaded = expectation(description: "legacy loaded")
        store.list { result in
            if case let .success(values) = result { XCTAssertEqual(values, [conversation]) }
            else { XCTFail("Legacy conversation should migrate") }
            loaded.fulfill()
        }
        wait(for: [loaded], timeout: 10)
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))
        let cleared = expectation(description: "cleared")
        store.clear { result in
            if case .failure = result { XCTFail("Clear should succeed") }
            cleared.fulfill()
        }
        wait(for: [cleared], timeout: 10)
        let restarted = expectation(description: "restart")
        SpaceGramConversationStore(mediaBoxPath: directory.appendingPathComponent("media").path).list { result in
            if case let .success(values) = result { XCTAssertTrue(values.isEmpty) }
            else { XCTFail("Restart should succeed") }
            restarted.fulfill()
        }
        wait(for: [restarted], timeout: 10)
    }

    func testDeletingBeforeFirstLoadMigratesThenRemovesLegacyConversation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let legacy = directory.appendingPathComponent("qwengram-conversations-v1")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let conversation = SpaceGramAIConversation(title: "Legacy")
        try JSONEncoder().encode(conversation).write(to: legacy.appendingPathComponent(conversation.id + ".json"))
        let store = SpaceGramConversationStore(mediaBoxPath: directory.appendingPathComponent("media").path)
        let removed = expectation(description: "removed before read")
        store.remove(id: conversation.id) { result in
            if case .failure = result { XCTFail("Legacy deletion should succeed") }
            removed.fulfill()
        }
        wait(for: [removed], timeout: 10)
        let loaded = expectation(description: "empty")
        store.list { result in
            if case let .success(values) = result { XCTAssertTrue(values.isEmpty) }
            else { XCTFail("Should load empty store") }
            loaded.fulfill()
        }
        wait(for: [loaded], timeout: 10)
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
        let saved = expectation(description: "saved")
        first.save(conversation) { result in
            if case .failure = result { XCTFail("Conversation should save") }
            saved.fulfill()
        }
        wait(for: [saved], timeout: 10)

        let reopened = SpaceGramConversationStore(mediaBoxPath: path)
        let loaded = expectation(description: "loaded")
        reopened.list { result in
            switch result {
            case let .success(conversations):
                XCTAssertEqual(conversations.count, 1)
                XCTAssertEqual(conversations.first?.id, conversation.id)
                XCTAssertEqual(conversations.first?.messages, [message])
            case .failure: XCTFail("Conversation should load")
            }
            loaded.fulfill()
        }
        wait(for: [loaded], timeout: 10)

        let removed = expectation(description: "removed")
        reopened.remove(id: conversation.id) { result in
            if case .failure = result { XCTFail("Conversation should delete") }
            removed.fulfill()
        }
        wait(for: [removed], timeout: 10)
        let empty = expectation(description: "empty")
        first.list { result in
            if case let .success(conversations) = result { XCTAssertTrue(conversations.isEmpty) }
            else { XCTFail("Store should remain readable") }
            empty.fulfill()
        }
        wait(for: [empty], timeout: 10)
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
        let saved = expectation(description: "saved")
        first.save(conversation) { result in
            if case .failure = result { XCTFail("Save failed") }
            saved.fulfill()
        }
        wait(for: [saved], timeout: 10)
        let loaded = expectation(description: "reloaded")
        first.list { result in
            guard case let .success(values) = result, let value = values.first else { XCTFail("Reload failed"); loaded.fulfill(); return }
            XCTAssertEqual(value.title, "Renamed")
            XCTAssertTrue(value.titleIsCustom)
            XCTAssertEqual(value.createdAt, created)
            XCTAssertEqual(value.messages.last?.content, "Partial answer")
            XCTAssertEqual(value.messages.last?.id, partial.id)
            loaded.fulfill()
        }
        wait(for: [loaded], timeout: 10)
        let isolated = expectation(description: "isolated")
        second.list { result in
            if case let .success(values) = result { XCTAssertTrue(values.isEmpty) }
            else { XCTFail("Other account unavailable") }
            isolated.fulfill()
        }
        wait(for: [isolated], timeout: 10)
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
        let loaded = expectation(description: "migration")
        store.list { result in
            guard case let .success(values) = result, values.count == 1 else { XCTFail("Valid v1 record should survive corrupt neighbor"); loaded.fulfill(); return }
            XCTAssertEqual(values[0].version, 2)
            XCTAssertEqual(values[0].title, "Old title")
            XCTAssertEqual(values[0].createdAt, values[0].updatedAt)
            XCTAssertFalse(values[0].titleIsCustom)
            XCTAssertEqual(values[0].messages[0].content, "Old question")
            XCTAssertFalse(values[0].messages[0].id.isEmpty)
            loaded.fulfill()
        }
        wait(for: [loaded], timeout: 10)
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
        let rejected = expectation(description: "size limit")
        store.save(oversized) { result in
            if case .success = result { XCTFail("Oversized conversation should be rejected") }
            rejected.fulfill()
        }
        wait(for: [rejected], timeout: 10)
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
            let saved = expectation(description: "saved \(title)")
            store.save(SpaceGramAIConversation(title: title)) { result in
                if case .failure = result { XCTFail("Save failed") }
                saved.fulfill()
            }
            wait(for: [saved], timeout: 10)
        }

        let cleared = expectation(description: "cleared")
        first.clear { result in
            if case .failure = result { XCTFail("Clear failed") }
            cleared.fulfill()
        }
        wait(for: [cleared], timeout: 10)

        let firstList = expectation(description: "first list")
        first.list { result in
            guard case let .success(values) = result else { XCTFail("First account unreadable"); firstList.fulfill(); return }
            XCTAssertTrue(values.isEmpty)
            firstList.fulfill()
        }
        let secondList = expectation(description: "second list")
        second.list { result in
            guard case let .success(values) = result else { XCTFail("Second account unreadable"); secondList.fulfill(); return }
            XCTAssertEqual(values.map(\.title), ["Second"])
            secondList.fulfill()
        }
        wait(for: [firstList, secondList], timeout: 10)
    }
}
