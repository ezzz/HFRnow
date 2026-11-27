import Foundation

/// A transport that lets identical GETs in flight share one exchange (#1397).
///
/// A screen that shows the same image in many cells (the smiley picker, avatars of one author repeated down a page, several
/// readers) asks for the same URL many times at once; without this each ask is its own request. Only a GET with no body is
/// merged, and only while the first one runs: nothing is remembered once it ends, so a failure is never replayed and a later
/// read is always a fresh exchange. Requests merge only when they are equal in every field (URL, headers, timeouts, redirect
/// policy, size cap), so a caller never gets an answer produced under rules other than its own.
///
/// The shared exchange runs in its own task: a caller that is cancelled stops waiting but does not abort it for the others.
public final class CoalescingTransport: HTTPTransport, @unchecked Sendable {
    private let base: any HTTPTransport
    private let lock = NSLock()
    private var inFlight: [(id: UUID, request: HTTPRequest, task: Task<Result<HTTPResponse, NetworkError>, Never>)] = []

    /// Merges the identical GETs sent through `base`.
    public init(base: any HTTPTransport) {
        self.base = base
    }

    /// Sends `request`, or joins the identical GET already in flight.
    public func perform(_ request: HTTPRequest) async throws(NetworkError) -> HTTPResponse {
        guard request.method == .get, request.body == nil else { return try await base.perform(request) }
        let task = join(request)
        return try await task.value.get()
    }

    private func join(_ request: HTTPRequest) -> Task<Result<HTTPResponse, NetworkError>, Never> {
        lock.lock()
        defer { lock.unlock() }
        if let existing = inFlight.first(where: { $0.request == request }) { return existing.task }
        let base = base
        let id = UUID()
        let task = Task<Result<HTTPResponse, NetworkError>, Never> { [weak self] in
            let outcome: Result<HTTPResponse, NetworkError>
            do throws(NetworkError) {
                outcome = .success(try await base.perform(request))
            } catch {
                outcome = .failure(error)
            }
            // Forgotten before anyone can see the result as "in flight": a later GET is a fresh exchange. Waits for `join` to
            // finish registering, which holds the lock.
            self?.forget(id)
            return outcome
        }
        inFlight.append((id, request, task))
        return task
    }

    private func forget(_ id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        inFlight.removeAll { $0.id == id }
    }
}
