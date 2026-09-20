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
    let isPerformingUpdate = ValuePromise<Bool>(false, ignoreRepeated: true)
    
    private var shouldKeepOnlinePresenceDisposable: Disposable?
    private let currentRequestDisposable = MetaDisposable()
    private var onlineTimer: SignalKitTimer?
    private var automaticOfflineTimer: SignalKitTimer?
    
    // MARK: NAGRAM — also publish offline on the first suppressed subscription.
    private var wasOnline: Bool?
    
    init(queue: Queue, shouldKeepOnlinePresence: Signal<Bool, NoError>, network: Network) {
        self.queue = queue
        self.network = network
        
        // MARK: NAGRAM — preserve the connection; only change explicit presence.
        let presenceInputs: Signal<(Bool, Bool, Bool), NoError> = combineLatest(
            shouldKeepOnlinePresence,
            spaceGramSuppressOnlinePresenceSignal(),
            spaceGramGoOfflineAutomaticallySignal()
        )
        let resolvedPresence: Signal<(Bool, Bool), NoError> = presenceInputs
        |> map { value in
            return (value.0 && !value.1, value.2)
        }
        let distinctPresence: Signal<(Bool, Bool), NoError> = resolvedPresence
        |> distinctUntilChanged(isEqual: { lhs, rhs in
            return lhs.0 == rhs.0 && lhs.1 == rhs.1
        })
        self.shouldKeepOnlinePresenceDisposable = (distinctPresence
        |> deliverOn(self.queue)).start(next: { [weak self] value in
            guard let `self` = self else {
                return
            }
            if self.wasOnline != value.0 {
                self.wasOnline = value.0
                self.updatePresence(value.0)
            }
            self.updateAutomaticOffline(value.1 && !value.0)
        })
    }
    
    deinit {
        assert(self.queue.isCurrent())
        self.shouldKeepOnlinePresenceDisposable?.dispose()
        self.currentRequestDisposable.dispose()
        self.onlineTimer?.invalidate()
        self.automaticOfflineTimer?.invalidate()
    }
    
    private func updatePresence(_ isOnline: Bool) {
        // MARK: NAGRAM — timers and queued signal callbacks must recheck the
        // current policy at the RPC boundary, not only at subscription time.
        let isOnline = isOnline && !SpaceGramGhostPolicy.suppressOnlinePresence
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
            request = self.network.request(Api.functions.account.updateStatus(offline: .boolFalse))
        } else {
            self.onlineTimer?.invalidate()
            self.onlineTimer = nil
            request = self.network.request(Api.functions.account.updateStatus(offline: .boolTrue))
        }
        self.isPerformingUpdate.set(true)
        self.currentRequestDisposable.set((request
        |> `catch` { _ -> Signal<Api.Bool, NoError> in
            return .single(.boolFalse)
        }
        |> deliverOn(self.queue)).start(completed: { [weak self] in
            guard let strongSelf = self else {
                return
            }
            strongSelf.isPerformingUpdate.set(false)
        }))
    }

    private func updateAutomaticOffline(_ enabled: Bool) {
        self.automaticOfflineTimer?.invalidate()
        self.automaticOfflineTimer = nil
        guard enabled else { return }
        let timer = SignalKitTimer(timeout: 25.0, repeat: true, completion: { [weak self] in
            self?.updatePresence(false)
        }, queue: self.queue)
        self.automaticOfflineTimer = timer
        timer.start()
    }
}

final class AccountPresenceManager {
    private let queue = Queue()
    private let impl: QueueLocalObject<AccountPresenceManagerImpl>
    
    init(shouldKeepOnlinePresence: Signal<Bool, NoError>, network: Network) {
        let queue = self.queue
        self.impl = QueueLocalObject(queue: self.queue, generate: {
            return AccountPresenceManagerImpl(queue: queue, shouldKeepOnlinePresence: shouldKeepOnlinePresence, network: network)
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
