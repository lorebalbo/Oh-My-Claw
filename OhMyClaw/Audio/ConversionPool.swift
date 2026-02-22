import Foundation

/// Bounds the number of concurrent ffmpeg conversions.
///
/// Uses an actor-internal semaphore pattern: callers that exceed
/// `maxConcurrent` are suspended via `CheckedContinuation` and
/// resumed FIFO when a slot opens.
///
/// Default concurrency limit is `ProcessInfo.processInfo.processorCount`
/// per requirement AUD-09.
actor ConversionPool {

    private let maxConcurrent: Int
    private var inFlight: Int = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(maxConcurrent: Int = ProcessInfo.processInfo.processorCount) {
        self.maxConcurrent = maxConcurrent
    }

    /// Acquires a conversion slot. Suspends the caller if all slots are in use.
    func acquire() async {
        if inFlight < maxConcurrent {
            inFlight += 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
        inFlight += 1
    }

    /// Releases a conversion slot, resuming the next waiting caller if any.
    func release() {
        inFlight -= 1
        if !waiters.isEmpty {
            let waiter = waiters.removeFirst()
            waiter.resume()
        }
    }
}
