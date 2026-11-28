import Foundation

/// A transport that lets identical GETs in flight share one exchange (#1397).
///
/// A screen that shows the same image in many cells (the smiley picker, avatars of one author repeated down a page, several
/// readers) asks for the same URL many times at once; without this each ask is its own request. Only a GET with no body is
/// merged, and only while the first one runs: nothing is remembered once it ends, so a failure is never replayed and a later
/// read is always a fresh exchange. Requests merge only when they are equal in every field (URL, headers, timeouts, redirect
/// policy, size cap), so a caller never gets an answer produced under rules other than its own.
///
/// Cancelling a caller ends its wait at once with `NetworkError.cancelled`; the exchange itself is cancelled when its last
/// waiter leaves, so a page that stops its images frees the connection as it would without this wrapper.
public final class CoalescingTransport: HTTPTransport, @unchecked Sendable {
    private typealias Outcome = Result<HTTPResponse, NetworkError>

    /// One caller waiting; every field is read and written under `lock`.
    private final class Waiter: @unchecked Sendable {
        var continuation: CheckedContinuation<Outcome, Never>?
        var exchange: Exchange?
        var isCancelled = false
    }

    /// One exchange in flight and the callers waiting for it; fields guarded by `lock`.
    private final class Exchange: @unchecked Sendable {
        let request: HTTPRequest
        var task: Task<Void, Never>?
        var waiters: [ObjectIdentifier: Waiter] = [:]

        init(request: HTTPRequest) { self.request = request }
    }

    /// The transport the exchanges go through (callers check it is the cookie-less one).
    public let base: any HTTPTransport
    private let lock = NSLock()
    private var inFlight: [Exchange] = []

    /// Callers waiting on an exchange now (tests wait for it to know that everyone joined).
    var waitingCallers: Int {
        lock.lock()
        defer { lock.unlock() }
        return inFlight.reduce(0) { $0 + $1.waiters.count }
    }

    /// Merges the identical GETs sent through `base`.
    public init(base: any HTTPTransport) {
        self.base = base
    }

    /// Sends `request`, or joins the identical GET already in flight.
    public func perform(_ request: HTTPRequest) async throws(NetworkError) -> HTTPResponse {
        guard request.method == .get, request.body == nil else { return try await base.perform(request) }
        let waiter = Waiter()
        let outcome = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Outcome, Never>) in
                join(waiter, continuation: continuation, request: request)
            }
        } onCancel: {
            leave(waiter)
        }
        return try outcome.get()
    }

    private func join(_ waiter: Waiter, continuation: CheckedContinuation<Outcome, Never>, request: HTTPRequest) {
        lock.lock()
        defer { lock.unlock() }
        // Cancelled before it could register: never starts nor joins anything.
        guard !waiter.isCancelled else { return continuation.resume(returning: .failure(.cancelled)) }
        waiter.continuation = continuation
        let exchange: Exchange
        if let existing = inFlight.first(where: { $0.request == request }) {
            exchange = existing
        } else {
            exchange = Exchange(request: request)
            inFlight.append(exchange)
            let base = base
            exchange.task = Task { [weak self] in
                let outcome: Outcome
                do throws(NetworkError) {
                    outcome = .success(try await base.perform(request))
                } catch {
                    outcome = .failure(error)
                }
                self?.finish(exchange, with: outcome)
            }
        }
        waiter.exchange = exchange
        exchange.waiters[ObjectIdentifier(waiter)] = waiter
    }

    /// The exchange ended: it is forgotten before its waiters resume, so a later GET is a fresh exchange.
    private func finish(_ exchange: Exchange, with outcome: Outcome) {
        lock.lock()
        inFlight.removeAll { $0 === exchange }
        let waiting = Array(exchange.waiters.values)
        exchange.waiters = [:]
        let continuations = waiting.compactMap { waiter -> CheckedContinuation<Outcome, Never>? in
            defer { waiter.continuation = nil }
            return waiter.continuation
        }
        lock.unlock()
        for continuation in continuations { continuation.resume(returning: outcome) }
    }

    /// A caller was cancelled: its wait ends, and the exchange is cancelled when nobody else waits for it.
    private func leave(_ waiter: Waiter) {
        lock.lock()
        waiter.isCancelled = true
        guard let continuation = waiter.continuation, let exchange = waiter.exchange else {
            lock.unlock()
            return
        }
        waiter.continuation = nil
        exchange.waiters[ObjectIdentifier(waiter)] = nil
        var abandoned: Task<Void, Never>?
        if exchange.waiters.isEmpty {
            inFlight.removeAll { $0 === exchange }
            abandoned = exchange.task
        }
        lock.unlock()
        abandoned?.cancel()
        continuation.resume(returning: .failure(.cancelled))
    }
}
