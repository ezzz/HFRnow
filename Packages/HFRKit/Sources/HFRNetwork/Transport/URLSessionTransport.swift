import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// `HTTPTransport` backed by `URLSession`. Never retries (POSTs must not be replayed) and does not touch TLS validation.
public final class URLSessionTransport: HTTPTransport {
    private let session: URLSession
    /// Same configuration (so same cookie storage) with a delegate that refuses redirects: a per-task delegate is
    /// ignored by swift-corelibs-foundation, so `RedirectPolicy.doNotFollow` needs a session-level one.
    private let noFollowSession: URLSession

    /// Uses `session`; LOT-042 passes one per account with its own cookie storage. The default is ephemeral and cookie-less.
    public init(session: URLSession = URLSessionTransport.makeDefaultSession()) {
        self.session = session
        self.noFollowSession = URLSession(configuration: session.configuration, delegate: NoRedirectDelegate(), delegateQueue: nil)
    }

    deinit {
        noFollowSession.finishTasksAndInvalidate()
    }

    /// An ephemeral session with no cookie handling.
    public static func makeDefaultSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration)
    }

    /// Sends the request. `timeout` is an idle limit: Apple's `URLSession` honours it through `timeoutInterval`, corelibs ignores
    /// it, so the transport watches the bytes received itself. `totalTimeout`, when set, caps the whole exchange.
    public func perform(_ request: HTTPRequest) async throws(NetworkError) -> HTTPResponse {
        guard let scheme = request.url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw .invalidRequest(reason: "URL scheme must be http or https")
        }
        let urlRequest = Self.makeURLRequest(request)
        do {
            let chosen = request.redirectPolicy == .doNotFollow ? noFollowSession : session
            let exchange: @Sendable () async throws -> HTTPResponse = {
                try await Self.exchange(request, urlRequest, on: chosen)
            }
            guard let total = request.totalTimeout else { return try await exchange() }
            return try await withDeadline(seconds: total, exchange)
        } catch {
            throw Self.map(error)
        }
    }

    private static func makeURLRequest(_ request: HTTPRequest) -> URLRequest {
        var urlRequest = URLRequest(
            url: request.url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: request.timeout
        )
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        for (name, value) in request.headers.fields { urlRequest.setValue(value, forHTTPHeaderField: name) }
        return urlRequest
    }

    /// One URLSession round trip converted to plain values.
    private static func exchange(
        _ request: HTTPRequest, _ urlRequest: URLRequest, on session: URLSession
    ) async throws -> HTTPResponse {
        let (data, response) = try await body(
            of: urlRequest, limit: request.maximumBodyBytes, idle: request.timeout,
            follows: request.redirectPolicy == .follow, on: session
        )
        guard let http = response as? HTTPURLResponse else { throw NetworkError.invalidResponse }
        var headers = HTTPHeaders()
        for (name, value) in http.allHeaderFields {
            if let name = name as? String, let value = value as? String { headers[name] = value }
        }
        return HTTPResponse(statusCode: http.statusCode, headers: headers, url: http.url ?? request.url, body: data)
    }

    /// The body and response; with a `limit`, read as a stream and abandoned as soon as it is known to exceed it.
    private static func body(
        of urlRequest: URLRequest, limit: Int?, idle: Double, follows: Bool, on session: URLSession
    ) async throws -> (Data, URLResponse) {
        guard let limit else { return try await dataWithIdleLimit(for: urlRequest, idle: idle, follows: follows, on: session) }
        #if canImport(FoundationNetworking)
        // swift-corelibs-foundation has no byte stream: the limit is checked once the body is in.
        let (data, response) = try await dataWithIdleLimit(for: urlRequest, idle: idle, follows: follows, on: session)
        guard data.count <= limit else { throw NetworkError.invalidResponse }
        return (data, response)
        #else
        let (bytes, response) = try await session.bytes(for: urlRequest)
        guard response.expectedContentLength <= Int64(limit) else {
            bytes.task.cancel()
            throw NetworkError.invalidResponse
        }
        var data = Data()
        data.reserveCapacity(Int(max(0, response.expectedContentLength)))
        for try await byte in bytes {
            guard data.count < limit else {
                bytes.task.cancel()
                throw NetworkError.invalidResponse
            }
            data.append(byte)
        }
        return (data, response)
        #endif
    }

    /// `session.data(for:)` with an idle limit. Apple's `URLSession` already treats `timeoutInterval` as one; swift-corelibs ignores it
    /// (and does not update `countOfBytesReceived` while a body streams in), so there a session delegate sees every chunk and the
    /// request fails with `URLError.timedOut` once none has arrived for `idle` seconds, a task that never receives one included.
    private static func dataWithIdleLimit(
        for urlRequest: URLRequest, idle: Double, follows: Bool, on session: URLSession
    ) async throws -> (Data, URLResponse) {
        #if canImport(FoundationNetworking)
        let delegate = IdleWatchDelegate(follows: follows, owner: session)
        // Same configuration, so the same cookie storage as the account's session.
        let watcher = URLSession(configuration: session.configuration, delegate: delegate, delegateQueue: nil)
        defer { watcher.finishTasksAndInvalidate() }
        return try await withThrowingTaskGroup(of: (Data, URLResponse).self) { group in
            group.addTask {
                try await withTaskCancellationHandler {
                    try await withCheckedThrowingContinuation { continuation in
                        delegate.start(watcher.dataTask(with: urlRequest), continuation)
                    }
                } onCancel: {
                    delegate.cancel()
                }
            }
            group.addTask {
                let poll = Duration.seconds(min(max(idle / 4, 0.01), 0.25))
                while true {
                    try await Task.sleep(for: poll)
                    if delegate.secondsSinceActivity >= max(idle, 0.001) { throw URLError(.timedOut) }
                }
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw URLError(.timedOut) }
            return first
        }
        #else
        return try await session.data(for: urlRequest)
        #endif
    }

    /// Runs `operation`, cancelling it and throwing `URLError.timedOut` once `seconds` have elapsed.
    private func withDeadline(
        seconds: Double,
        _ operation: @escaping @Sendable () async throws -> HTTPResponse
    ) async throws -> HTTPResponse {
        try await withThrowingTaskGroup(of: HTTPResponse.self) { group in
            group.addTask(operation: operation)
            group.addTask {
                try await Task.sleep(for: .seconds(max(seconds, 0.001)))
                throw URLError(.timedOut)
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw URLError(.timedOut) }
            return first
        }
    }

    /// Maps any thrown error to a `NetworkError`.
    static func map(_ error: any Error) -> NetworkError {
        if let known = error as? NetworkError { return known }
        if error is CancellationError { return .cancelled }
        guard let urlError = error as? URLError else { return .transport(code: (error as NSError).code) }
        switch urlError.code {
        case .cancelled: return .cancelled
        case .timedOut: return .timedOut
        case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff: return .offline
        default: return .transport(code: urlError.errorCode)
        }
    }
}

#if canImport(FoundationNetworking)
/// Collects one data task's answer and remembers when data last arrived (the idle watcher of `dataWithIdleLimit`).
private final class IdleWatchDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let follows: Bool
    /// The session the request was made for: its delegate (an account session's host policy, LESSONS 30) still decides redirects.
    private let owner: URLSession
    private var task: URLSessionDataTask?
    private var cancelled = false
    private var body = Data()
    private var response: URLResponse?
    private var continuation: CheckedContinuation<(Data, URLResponse), any Error>?
    private var lastActivity = ContinuousClock.now

    init(follows: Bool, owner: URLSession) {
        self.follows = follows
        self.owner = owner
    }

    func start(_ task: URLSessionDataTask, _ continuation: CheckedContinuation<(Data, URLResponse), any Error>) {
        lock.lock()
        self.task = task
        self.continuation = continuation
        lastActivity = .now
        let alreadyCancelled = cancelled
        lock.unlock()
        if alreadyCancelled { task.cancel() } else { task.resume() }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let task = task
        lock.unlock()
        task?.cancel()
    }

    var secondsSinceActivity: Double {
        lock.lock()
        defer { lock.unlock() }
        let elapsed = ContinuousClock.now - lastActivity
        return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    }

    func urlSession(
        _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        lock.lock()
        self.response = response
        lastActivity = .now
        lock.unlock()
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        lock.lock()
        body.append(data)
        lastActivity = .now
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
        let result: Result<(Data, URLResponse), any Error>
        if let error {
            result = .failure(error)
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

/// Task delegate that refuses every redirect so the 3xx answer is delivered as is.
private final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
