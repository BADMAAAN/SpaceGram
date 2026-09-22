import SwiftSignalKit

/// Owns exactly one translator request for the lifetime of its screen.
/// A token prevents a completion from an older session from updating a reopened screen.
public final class SpaceGramTranslatorRequestLifecycle {
    private let disposable = MetaDisposable()
    private var generation: UInt64 = 0
    private var activeToken: UInt64?

    public init() {
    }

    deinit {
        self.cancel()
    }

    public func begin() -> UInt64 {
        self.generation &+= 1
        self.activeToken = self.generation
        self.disposable.set(nil)
        return self.generation
    }

    public func setDisposable(_ disposable: Disposable, for token: UInt64) {
        guard self.activeToken == token else {
            disposable.dispose()
            return
        }
        self.disposable.set(disposable)
    }

    @discardableResult
    public func finish(_ token: UInt64) -> Bool {
        guard self.activeToken == token else {
            return false
        }
        self.activeToken = nil
        self.disposable.set(nil)
        return true
    }

    public func cancel() {
        self.generation &+= 1
        self.activeToken = nil
        self.disposable.set(nil)
    }
}
