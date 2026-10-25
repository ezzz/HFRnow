import Foundation
/// In-memory `HTTPTransport` for tests of this and later lots: scripted replies, recorded requests.
///
/// It lives in the module (not a test-support target) so `HFRClientTests` and the app's previews can use it
/// without a new product; it is ~50 lines and holds no global state. It does not simulate redirects: script the
/// final `HTTPResponse.url`, or a 3xx with `Location` for `RedirectPolicy.doNotFollow`.
public actor MockTransport: HTTPTransport {
    /// Computes the reply for a request.
    public typealias Handler = @Sendable (HTTPRequest) async throws(NetworkError) -> HTTPResponse

    private var handler: Handler
    /// Every request received, in order.
    public private(set) var requests: [HTTPRequest] = []

    /// Replies with whatever `handler` returns.
    public init(handler: @escaping Handler) {
        self.handler = handler
    }

    /// Replies with `replies` in order, then fails with `NetworkError.unscripted`.
    public init(replies: [Result<HTTPResponse, NetworkError>]) {
        let queue = ReplyQueue(replies)
        self.handler = { _ async throws(NetworkError) -> HTTPResponse in try queue.next().get() }
    }

    /// Records the request and returns the scripted reply.
    public func perform(_ request: HTTPRequest) async throws(NetworkError) -> HTTPResponse {
        requests.append(request)
        return try await handler(request)
    }
}

/// Lock-protected FIFO of scripted replies.
private final class ReplyQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var replies: [Result<HTTPResponse, NetworkError>]

    init(_ replies: [Result<HTTPResponse, NetworkError>]) { self.replies = replies }

    func next() -> Result<HTTPResponse, NetworkError> {
        lock.lock()
        defer { lock.unlock() }
        return replies.isEmpty ? .failure(.unscripted) : replies.removeFirst()
    }
}
