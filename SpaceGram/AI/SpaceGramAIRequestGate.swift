import Foundation
import SpaceGramSettings

// Owned for the lifetime of a request. Disabling SpaceGram also cancels requests
// started by a controller that is no longer visible (including another account).
final class SpaceGramAIRequestGate {
    private let lock = NSLock()
    private var task: URLSessionTask?
    private var observer: NSObjectProtocol?
    private var disabled = false

    var wasDisabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return disabled
    }

    init() {
        observer = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: UserDefaults.standard, queue: nil) { [weak self] _ in
            self?.checkSettings()
        }
        checkSettings()
    }

    deinit {
        if let observer = observer {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func start(_ task: URLSessionTask) {
        lock.lock()
        self.task = task
        let disabled = self.disabled || !SpaceGramSettings.shared.spaceGramEnabled
        self.disabled = disabled
        lock.unlock()
        if disabled {
            task.cancel()
        } else {
            task.resume()
        }
    }

    func finish() {
        lock.lock()
        task = nil
        lock.unlock()
    }

    private func checkSettings() {
        guard !SpaceGramSettings.shared.spaceGramEnabled else {
            return
        }
        lock.lock()
        disabled = true
        let task = self.task
        lock.unlock()
        task?.cancel()
    }
}
