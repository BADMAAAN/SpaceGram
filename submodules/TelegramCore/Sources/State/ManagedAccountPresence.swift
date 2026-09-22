import Foundation
// MARK: NAGRAM — SpaceGram presence policy.
import SpaceGramSettings
import SpaceGramSettingsSignal
import TelegramApi
import Postbox
import SwiftSignalKit
import MtProtoKit

private typealias SignalKitTimer = SwiftSignalKit.Timer


private final class AccountPresenceManagerImpl {
    private let queue: Queue
    private let network: Network
    private let postbox: Postbox // MARK: NAGRAM — confirmed self-presence cache.
    let isPerformingUpdate = ValuePromise<Bool>(false, ignoreRepeated: true)
    
    private var shouldKeepOnlinePresenceDisposable: Disposable?
    private let currentRequestDisposable = MetaDisposable()
    private var onlineTimer: SignalKitTimer?
    
    // MARK: NAGRAM — nil forces a fresh native transition after suppression ends.
    private var wasOnline: Bool?
    
    init(queue: Queue, shouldKeepOnlinePresence: Signal<Bool, NoError>, network: Network, postbox: Postbox) {
        self.queue = queue
        self.network = network
        self.postbox = postbox
        
        // MARK: NAGRAM — preserve the connection; only change explicit presence.
        let presenceInputs: Signal<(Bool, Bool), NoError> = combineLatest(
            shouldKeepOnlinePresence,
            spaceGramSuppressOnlinePresenceSignal()
        )
        let distinctPresence: Signal<(Bool, Bool), NoError> = presenceInputs
        |> distinctUntilChanged(isEqual: { lhs, rhs in
            return lhs.0 == rhs.0 && lhs.1 == rhs.1
        })
        self.shouldKeepOnlinePresenceDisposable = (distinctPresence
        |> deliverOn(self.queue)).start(next: { [weak self] value in
            guard let `self` = self else {
                return
            }
            let (shouldBeOnline, suppressPresence) = value
            if suppressPresence {
                // MARK: NAGRAM — authoritative Ghost semantics: never convert
                // suppression into an explicit offline RPC. That RPC has no
                // timestamp parameter and can replace the server's was_online.
                self.wasOnline = nil
                self.onlineTimer?.invalidate()
                self.onlineTimer = nil
                self.currentRequestDisposable.set(nil)
                self.isPerformingUpdate.set(false)
                Logger.shared.log("SpaceGramPresence", "presence RPC suppressed; waiting for server status expiry")
            } else if self.wasOnline != shouldBeOnline {
                self.wasOnline = shouldBeOnline
                self.updatePresence(shouldBeOnline)
            }
        })
    }
    
    deinit {
        assert(self.queue.isCurrent())
        self.shouldKeepOnlinePresenceDisposable?.dispose()
        self.currentRequestDisposable.dispose()
        self.onlineTimer?.invalidate()
    }
    
    private func updatePresence(_ isOnline: Bool) {
        // MARK: NAGRAM — timers and queued signal callbacks must recheck the
        // current policy at the RPC boundary, not only at subscription time.
        guard !SpaceGramGhostPolicy.suppressOnlinePresence else {
            self.onlineTimer?.invalidate()
            self.onlineTimer = nil
            Logger.shared.log("SpaceGramPresence", "presence RPC cancelled at request boundary")
            return
        }
        let request: Signal<Api.Bool, MTRpcError>
        if isOnline {
            let timer = SignalKitTimer(timeout: 30.0, repeat: false, completion: { [weak self] in
                guard let strongSelf = self else {
                    return
                }
                strongSelf.updatePresence(true)
            }, queue: self.queue)
            self.onlineTimer = timer
            timer.start()
            Logger.shared.log("SpaceGramPresence", "account.updateStatus offline=false")
            request = self.network.request(Api.functions.account.updateStatus(offline: .boolFalse))
        } else {
            self.onlineTimer?.invalidate()
            self.onlineTimer = nil
            Logger.shared.log("SpaceGramPresence", "account.updateStatus offline=true")
            request = self.network.request(Api.functions.account.updateStatus(offline: .boolTrue))
        }
        self.isPerformingUpdate.set(true)
        // MARK: NAGRAM — corrected request time, published only after server ACK.
        let presenceTimestamp = Int32(exactly: floor(self.network.globalTime))
        self.currentRequestDisposable.set((request
        |> `catch` { _ -> Signal<Api.Bool, NoError> in
            return .single(.boolFalse)
        }
        |> deliverOn(self.queue)).start(next: { [weak self] result in
            guard let self, isOnline, case .boolTrue = result, let presenceTimestamp else { return }
            let _ = self.postbox.transaction { transaction -> Void in
                spaceGramStoreSelfPresence(transaction: transaction, timestamp: presenceTimestamp)
            }.start()
        }, completed: { [weak self] in
            guard let strongSelf = self else {
                return
            }
            Logger.shared.log("SpaceGramPresence", "account.updateStatus completed offline=\(!isOnline)")
            strongSelf.isPerformingUpdate.set(false)
        }))
    }
}

final class AccountPresenceManager {
    private let queue = Queue()
    private let impl: QueueLocalObject<AccountPresenceManagerImpl>
    
    init(shouldKeepOnlinePresence: Signal<Bool, NoError>, network: Network, postbox: Postbox) {
        let queue = self.queue
        self.impl = QueueLocalObject(queue: self.queue, generate: {
            return AccountPresenceManagerImpl(queue: queue, shouldKeepOnlinePresence: shouldKeepOnlinePresence, network: network, postbox: postbox)
        })
    }
    
    func isPerformingUpdate() -> Signal<Bool, NoError> {
        return Signal { subscriber in
            let disposable = MetaDisposable()
            self.impl.with { impl in
                disposable.set(impl.isPerformingUpdate.get().start(next: { value in
                    subscriber.putNext(value)
                }))
            }
            return disposable
        }
    }
}
