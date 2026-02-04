import Foundation

final class AsyncSemaphore: @unchecked Sendable {
    private let lock = NSLock()
    private var permits: Int
    private var waiters: [Waiter] = []

    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Never>
    }

    init(value: Int) {
        self.permits = max(0, value)
    }

    func wait() async {
        if Task.isCancelled { return }
        let waiterId = UUID()
        await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                lock.lock()
                if Task.isCancelled {
                    lock.unlock()
                    continuation.resume()
                    return
                }
                if permits > 0 {
                    permits -= 1
                    lock.unlock()
                    continuation.resume()
                } else {
                    waiters.append(Waiter(id: waiterId, continuation: continuation))
                    lock.unlock()
                }
            }
        }, onCancel: {
            lock.lock()
            if let index = waiters.firstIndex(where: { $0.id == waiterId }) {
                let waiter = waiters.remove(at: index)
                lock.unlock()
                waiter.continuation.resume()
            } else {
                lock.unlock()
            }
        })
    }

    func signal() {
        lock.lock()
        if !waiters.isEmpty {
            let continuation = waiters.removeFirst().continuation
            lock.unlock()
            continuation.resume()
        } else {
            permits += 1
            lock.unlock()
        }
    }
}
