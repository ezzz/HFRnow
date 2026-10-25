import Foundation
/// HTTP verbs used by the forum.
public enum HTTPMethod: String, Sendable, Equatable {
    case get = "GET"
    case post = "POST"
    case head = "HEAD"
}

/// Whether the transport follows 3xx answers.
public enum RedirectPolicy: Sendable, Equatable {
    /// Follow redirects and report the final URL (default; permalink to page URL).
    case follow
    /// Return the 3xx answer itself so the caller can read `Location` (intra-topic search).
    case doNotFollow
}

/// Per-endpoint time limits, in seconds, ported from the legacy constants.
public enum RequestTimeout {
    /// Lists, topic pages, forums (legacy `kTimeoutMini`).
    public static let standard: Double = 30
    /// Intra-topic search (legacy `kTimeoutMaxi`).
    public static let topicSearch: Double = 60
    /// Global search.
    public static let globalSearch: Double = 15
    /// Background private-message check.
    public static let background: Double = 5
}

/// An HTTP request as plain data, independent of `URLSession`.
public struct HTTPRequest: Sendable, Equatable {
    /// Absolute `http` or `https` URL.
    public var url: URL
    /// HTTP verb.
    public var method: HTTPMethod
    /// Request headers.
    public var headers: HTTPHeaders
    /// Raw body, if any.
    public var body: Data?
    /// Total time limit in seconds for the whole exchange.
    public var timeout: Double
    /// Redirect handling for this request.
    public var redirectPolicy: RedirectPolicy

    /// Creates a request; defaults to a followed GET with the standard timeout.
    public init(
        url: URL,
        method: HTTPMethod = .get,
        headers: HTTPHeaders = [:],
        body: Data? = nil,
        timeout: Double = RequestTimeout.standard,
        redirectPolicy: RedirectPolicy = .follow
    ) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
        self.timeout = timeout
        self.redirectPolicy = redirectPolicy
    }

    /// A GET request.
    public static func get(
        _ url: URL,
        headers: HTTPHeaders = [:],
        timeout: Double = RequestTimeout.standard,
        redirectPolicy: RedirectPolicy = .follow
    ) -> HTTPRequest {
        HTTPRequest(url: url, headers: headers, timeout: timeout, redirectPolicy: redirectPolicy)
    }

    /// A form POST; sets the content type. POSTs are never retried by the transport.
    public static func post(
        _ url: URL,
        form: FormBody,
        headers: HTTPHeaders = [:],
        timeout: Double = RequestTimeout.standard,
        redirectPolicy: RedirectPolicy = .follow
    ) -> HTTPRequest {
        var headers = headers
        headers["Content-Type"] = FormBody.contentType
        return HTTPRequest(
            url: url, method: .post, headers: headers, body: form.data,
            timeout: timeout, redirectPolicy: redirectPolicy
        )
    }
}
