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

    /// Sends the request; `timeout` is also enforced here as a total deadline because corelibs ignores `timeoutInterval`.
    public func perform(_ request: HTTPRequest) async throws(NetworkError) -> HTTPResponse {
        guard let scheme = request.url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            throw .invalidRequest(reason: "URL scheme must be http or https")
        }
        let urlRequest = Self.makeURLRequest(request)
        do {
            let chosen = request.redirectPolicy == .doNotFollow ? noFollowSession : session
            let fallbackURL = request.url
            return try await withDeadline(seconds: request.timeout) {
                try await Self.exchange(urlRequest, fallbackURL: fallbackURL, on: chosen)
            }
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
    private static func exchange(_ urlRequest: URLRequest, fallbackURL: URL, on session: URLSession) async throws -> HTTPResponse {
        let (data, response) = try await session.data(for: urlRequest)
        guard let http = response as? HTTPURLResponse else { throw NetworkError.invalidResponse }
        var headers = HTTPHeaders()
        for (name, value) in http.allHeaderFields {
            if let name = name as? String, let value = value as? String { headers[name] = value }
        }
        return HTTPResponse(statusCode: http.statusCode, headers: headers, url: http.url ?? fallbackURL, body: data)
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
