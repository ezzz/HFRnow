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
    /// DO NOT MERGE (#1276): trace id of this transport's session.
    private let traceID = T1276.nextSessionID()

    /// Uses `session`; LOT-042 passes one per account with its own cookie storage. The default is ephemeral and cookie-less.
    public init(session: URLSession = URLSessionTransport.makeDefaultSession()) {
        self.session = session
        self.noFollowSession = URLSession(configuration: session.configuration, delegate: NoRedirectDelegate(), delegateQueue: nil)
        T1276.logSession(traceID, kind: session.configuration.httpShouldSetCookies ? "jar" : "anon", session.configuration)
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
        // DO NOT MERGE (#1276): one line at the start and one at the end of every request.
        let trace = T1276.nextRequestID()
        let started = ProcessInfo.processInfo.systemUptime
        let place = T1276.place(request.url)
        let method = request.method.rawValue
        let total = request.totalTimeout.map { "\($0)" } ?? "-"
        T1276.log(
            "req r\(trace) start s\(traceID) \(method) \(place) idle=\(request.timeout) total=\(total) "
                + "follow=\(request.redirectPolicy == .follow) limit=\(request.maximumBodyBytes != nil) inFlight=\(T1276.began())"
        )
        func elapsed() -> Int { Int((ProcessInfo.processInfo.systemUptime - started) * 1000) }
        do {
            let chosen = request.redirectPolicy == .doNotFollow ? noFollowSession : session
            let exchange: @Sendable () async throws -> HTTPResponse = {
                try await Self.exchange(request, urlRequest, on: chosen, trace: trace)
            }
            let response: HTTPResponse
            if let total = request.totalTimeout {
                response = try await withDeadline(seconds: total, exchange)
            } else {
                response = try await exchange()
            }
            T1276.log(
                "req r\(trace) end s\(traceID) \(method) \(place) \(elapsed())ms status=\(response.statusCode) "
                    + "bytes=\(response.body.count) final=\(T1276.place(response.url)) inFlight=\(T1276.ended())"
            )
            return response
        } catch {
            T1276.log(
                "req r\(trace) end s\(traceID) \(method) \(place) \(elapsed())ms error=\(T1276.describe(error)) "
                    + "taskCancelled=\(Task.isCancelled) inFlight=\(T1276.ended())"
            )
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
        _ request: HTTPRequest, _ urlRequest: URLRequest, on session: URLSession, trace: Int
    ) async throws -> HTTPResponse {
        let (data, response) = try await body(
            of: urlRequest, limit: request.maximumBodyBytes, idle: request.timeout,
            follows: request.redirectPolicy == .follow, on: session, trace: trace
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
        of urlRequest: URLRequest, limit: Int?, idle: Double, follows: Bool, on session: URLSession, trace: Int
    ) async throws -> (Data, URLResponse) {
        guard let limit else {
            return try await dataWithIdleLimit(for: urlRequest, idle: idle, follows: follows, on: session, trace: trace)
        }
        #if canImport(FoundationNetworking)
        // swift-corelibs-foundation has no byte stream: the limit is checked once the body is in.
        let (data, response) = try await dataWithIdleLimit(
            for: urlRequest, idle: idle, follows: follows, on: session, trace: trace
        )
        guard data.count <= limit else { throw NetworkError.invalidResponse }
        return (data, response)
        #else
        let (bytes, response) = try await session.bytes(for: urlRequest, delegate: T1276MetricsDelegate(requestID: trace))
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        T1276.log("req r\(trace) headers status=\(status) expected=\(response.expectedContentLength)")
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
    /// Only received bytes count: a request body that takes longer than `idle` to send (a large upload) fails on Linux, which
    /// Apple's `timeoutInterval` does not do. The Linux build is for tests and CI, it does not ship.
    private static func dataWithIdleLimit(
        for urlRequest: URLRequest, idle: Double, follows: Bool, on session: URLSession, trace: Int
    ) async throws -> (Data, URLResponse) {
        #if canImport(FoundationNetworking)
        let delegate = IdleWatchDelegate(follows: follows, idle: idle, owner: session)
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
                let clock = ContinuousClock()
                while true {
                    let slept = try await clock.measure { try await Task.sleep(for: poll) }
                    // A sleep as long as the whole limit means this process was stalled (suspended app, starved machine), not the
                    // network: the chunks it could not receive meanwhile are no evidence of an idle connection.
                    if slept >= .seconds(max(idle, 0.001)) { delegate.noteActivity() }
                    if delegate.secondsSinceActivity >= max(idle, 0.001) { throw URLError(.timedOut) }
                }
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw URLError(.timedOut) }
            return first
        }
        #else
        return try await session.data(for: urlRequest, delegate: T1276MetricsDelegate(requestID: trace))
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
