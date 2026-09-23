import Foundation

public struct SpaceGramLocalReadBoundary: Codable, Equatable {
    public let accountId: Int64
    public let peerId: Int64
    public let threadId: Int64?
    public let namespace: Int32
    public let messageId: Int32
    public let timestamp: Int32
    public let serverUnreadCount: Int32

    fileprivate func isBefore(messageId: Int32, timestamp: Int32) -> Bool {
        if self.timestamp != timestamp {
            return self.timestamp < timestamp
        }
        return self.messageId < messageId
    }
}

/// Account-local Ghost read progress. This never mutates Telegram/Postbox read
/// state, so persisting it cannot enqueue a server read operation.
public final class SpaceGramLocalReadState {
    public static let shared = SpaceGramLocalReadState(defaults: .standard)

    private static let storageKey = "spacegram.localRead.boundaries.v1"
    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public func boundary(accountId: Int64, peerId: Int64, threadId: Int64?, namespace: Int32) -> SpaceGramLocalReadBoundary? {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.load().first(where: {
            $0.accountId == accountId && $0.peerId == peerId && $0.threadId == threadId && $0.namespace == namespace
        })
    }

    @discardableResult
    public func advance(
        accountId: Int64,
        peerId: Int64,
        threadId: Int64?,
        namespace: Int32,
        messageId: Int32,
        timestamp: Int32,
        serverUnreadCount: Int32
    ) -> SpaceGramLocalReadBoundary {
        self.lock.lock()
        defer { self.lock.unlock() }

        var values = self.load()
        let index = values.firstIndex(where: {
            $0.accountId == accountId && $0.peerId == peerId && $0.threadId == threadId && $0.namespace == namespace
        })
        if let index, !values[index].isBefore(messageId: messageId, timestamp: timestamp) {
            return values[index]
        }

        let value = SpaceGramLocalReadBoundary(
            accountId: accountId,
            peerId: peerId,
            threadId: threadId,
            namespace: namespace,
            messageId: messageId,
            timestamp: timestamp,
            serverUnreadCount: max(0, serverUnreadCount)
        )
        if let index {
            values[index] = value
        } else {
            values.append(value)
        }
        self.save(values)
        return value
    }

    public func derivedUnreadCount(
        accountId: Int64,
        peerId: Int64,
        threadId: Int64?,
        namespace: Int32,
        serverUnreadCount: Int32,
        serverMaxIncomingMessageId: Int32? = nil
    ) -> Int32 {
        guard let value = self.boundary(accountId: accountId, peerId: peerId, threadId: threadId, namespace: namespace) else {
            return max(0, serverUnreadCount)
        }
        if let serverMaxIncomingMessageId, serverMaxIncomingMessageId >= value.messageId {
            return max(0, serverUnreadCount)
        }
        return max(0, serverUnreadCount - value.serverUnreadCount)
    }

    private func load() -> [SpaceGramLocalReadBoundary] {
        guard let data = self.defaults.data(forKey: Self.storageKey),
              let values = try? JSONDecoder().decode([SpaceGramLocalReadBoundary].self, from: data) else {
            return []
        }
        return values
    }

    private func save(_ values: [SpaceGramLocalReadBoundary]) {
        guard let data = try? JSONEncoder().encode(values) else { return }
        self.defaults.set(data, forKey: Self.storageKey)
    }
}
