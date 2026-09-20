import Foundation
import Postbox
import SpaceGramSettings
import SwiftSignalKit
import TelegramApi

// Account-lifetime authorization for the read-state sync worker. Enqueueing a
// message never grants this permission. A restart safely forgets permissions.
final class SpaceGramReadPermissions {
    private let indices = Atomic<[PeerId: Int32]>(value: [:])
    let changes = ValuePromise<[PeerId: Int32]>([:])

    func allows(peerId: PeerId, maxId: Int32) -> Bool {
        return self.indices.with { ($0[peerId] ?? 0) >= maxId }
    }

    func allow(_ index: MessageIndex) {
        let updated = self.indices.modify { values in
            var values = values
            values[index.id.peerId] = max(values[index.id.peerId] ?? 0, index.id.id)
            return values
        }
        self.changes.set(updated)
    }
}

// Contract: a successful immediate cloud send/reply or ordinary reaction reads
// through that message, in that conversation only. Scheduled ACKs never call this.
func spaceGramReadOnSuccessfulInteraction(transaction: Transaction, stateManager: AccountStateManager, message: Message) {
    guard SpaceGramGhostPolicy.shouldReadOnInteraction,
          message.id.namespace == Namespaces.Message.Cloud,
          message.id.peerId.namespace != Namespaces.Peer.SecretChat else { return }
    if let threadId = message.threadId {
        guard let peer = transaction.getPeer(message.id.peerId), let inputPeer = apiInputPeer(peer) else { return }
        let subPeer = peer.isMonoForum ? transaction.getPeer(PeerId(threadId)).flatMap(apiInputPeer) : nil
        if peer.isMonoForum && subPeer == nil { return }
        if var data = transaction.getMessageHistoryThreadInfo(peerId: peer.id, threadId: threadId)?.data.get(MessageHistoryThreadData.self), message.id.id > data.maxIncomingReadId {
            if let count = transaction.getThreadMessageCount(peerId: peer.id, threadId: threadId, namespace: Namespaces.Message.Cloud, fromIdExclusive: data.maxIncomingReadId, toIndex: message.index) {
                data.incomingUnreadCount = max(0, data.incomingUnreadCount - Int32(clamping: count))
            }
            data.maxIncomingReadId = message.id.id
            data.maxKnownMessageId = max(data.maxKnownMessageId, message.id.id)
            if let entry = StoredMessageHistoryThreadInfo(data) {
                transaction.setMessageHistoryThreadInfo(peerId: peer.id, threadId: threadId, info: entry)
            }
        }
        if let subPeer {
            let _ = stateManager.network.request(Api.functions.messages.readSavedHistory(parentPeer: inputPeer, peer: subPeer, maxId: message.id.id)).start()
        } else {
            let _ = stateManager.network.request(Api.functions.messages.readDiscussion(peer: inputPeer, msgId: Int32(clamping: threadId), readMaxId: message.id.id)).start()
        }
    } else {
        guard transaction.getPeer(message.id.peerId)?.isForumOrMonoForum != true else { return }
        stateManager.spaceGramReadPermissions.allow(message.index)
        _internal_applyMaxReadIndexInteractively(transaction: transaction, stateManager: stateManager, index: message.index)
    }
}
