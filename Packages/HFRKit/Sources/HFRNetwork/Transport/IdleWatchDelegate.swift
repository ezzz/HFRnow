import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking

/// Collects one data task's answer and keeps the two clocks of the idle limit (the Linux idle watcher of
/// `URLSessionTransport`: swift-corelibs ignores `timeoutInterval`, and does not update `countOfBytesReceived` while a body
/// streams in, so each chunk is seen here).
///
/// - `lastReceived`: when the task started or last received a response or data. Only the network moves it. The mapping of a
///   failure to `timedOut` reads it when the connection ends.
/// - `lastActivity`: the same, and the watcher also restarts it when it finds that its own sleep lasted as long as the limit
///   (the process was stalled, not the network). The watcher reads it to decide a timeout.
/// They are separate on purpose: if the watcher's restart moved `lastReceived`, a server that dropped a connection that had
/// been quiet for the limit, just after a stall, would read as a short silence and give a transport error (#1087).
final class IdleWatchDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let follows: Bool
    /// The idle limit in seconds; at least a millisecond, as the watcher reads it.
    private let idle: Double
    /// The session the request was made for: its delegate (an account session's host policy, LESSONS 30) still decides
    /// redirects.
    private let owner: URLSession
    private let now: @Sendable () -> ContinuousClock.Instant
    private var task: URLSessionDataTask?
    private var cancelled = false
    private var body = Data()
    private var response: URLResponse?
    private var continuation: CheckedContinuation<(Data, URLResponse), any Error>?
    private var lastReceived: ContinuousClock.Instant
    private var lastActivity: ContinuousClock.Instant

    /// A delegate for a request with idle limit `idle`; `now` is the clock, replaced in tests.
    init(
        follows: Bool, idle: Double, owner: URLSession, now: @escaping @Sendable () -> ContinuousClock.Instant = { .now }
    ) {
        self.follows = follows
        self.idle = max(idle, 0.001)
        self.owner = owner
        self.now = now
        lastReceived = now()
        lastActivity = lastReceived
    }

    /// Starts `task`, whose answer resumes `continuation`; the clocks start now.
    func start(_ task: URLSessionDataTask, _ continuation: CheckedContinuation<(Data, URLResponse), any Error>) {
        if attach(task, continuation) { task.cancel() } else { task.resume() }
    }

    /// Records `task` and `continuation` and starts the clocks, without starting the task; true when a cancellation came first.
    func attach(_ task: URLSessionDataTask, _ continuation: CheckedContinuation<(Data, URLResponse), any Error>) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        self.task = task
        self.continuation = continuation
        lastReceived = now()
        lastActivity = lastReceived
        return cancelled
    }

    /// Cancels the task, now or as soon as it starts.
    func cancel() {
        lock.lock()
        cancelled = true
        let task = task
        lock.unlock()
        task?.cancel()
    }

    /// The watcher found that the process was stalled: restarts its clock, never the network's.
    func noteActivity() {
        lock.lock()
        lastActivity = now()
        lock.unlock()
    }

    /// Seconds since the watcher's clock was last restarted or the network last sent something.
    var secondsSinceActivity: Double {
        lock.lock()
        defer { lock.unlock() }
        return Self.seconds(now() - lastActivity)
    }

    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        lock.lock()
        self.response = response
        lastReceived = now()
        lastActivity = lastReceived
        lock.unlock()
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        body.append(data)
        lastReceived = now()
        lastActivity = lastReceived
        lock.unlock()
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        guard follows else { return completionHandler(nil) }
        if let inner = owner.delegate as? any URLSessionTaskDelegate {
            inner.urlSession(
                owner, task: task, willPerformHTTPRedirection: response, newRequest: request, completionHandler: completionHandler
            )
        } else {
            completionHandler(request)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        // The silence is measured here, when the connection ends, from what the network last sent, not by the watcher: a
        // watcher that cannot run (a starved executor) or that restarted its clock after a stall must not let a server that
        // dropped a quiet connection after the limit turn a timeout into a transport error (#1087). A cancellation (the
        // caller's, or the watcher's own after its timeout) stays a cancellation.
        let silentSeconds = Self.seconds(now() - lastReceived)
        let result: Result<(Data, URLResponse), any Error>
        if let error {
            let cancelled = (error as? URLError)?.code == .cancelled
            result = .failure(!cancelled && silentSeconds >= idle ? URLError(.timedOut) : error)
        } else if let response {
            result = .success((body, response))
        } else {
            result = .failure(URLError(.badServerResponse))
        }
        lock.unlock()
        continuation?.resume(with: result)
    }
}
#endif
