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

/// Per-endpoint time limits, in seconds: legacy 4.0.x at `2fe43da3` (`ae196aa0`, operator decision on #683). Every value is an
/// idle limit (`HTTPRequest.timeout`); only global search also caps the whole transfer.
public enum RequestTimeout {
    /// Lists, topic pages, forums (legacy `kTimeoutMini`, `Classes/Constants.h:71`).
    public static let standard: Double = 10
    /// Intra-topic search (legacy `kTimeoutMaxi`, `Classes/Constants.h:72`).
    public static let topicSearch: Double = 10
    /// Global search, idle (legacy `TIME_OUT_INTERVAL_SEARCH`, `Classes/ObjCForumSearchWorker.m:8,131`).
    public static let globalSearch: Double = 10
    /// Global search, whole transfer (legacy `timeoutIntervalForResource`, `Classes/ObjCForumSearchWorker.m:132`).
    public static let globalSearchTotal: Double = 10
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
    /// Idle limit in seconds: the request fails when no data arrives for that long (legacy `URLRequest.timeoutInterval`
    /// semantics); a slow answer that keeps flowing is not cut.
    public var timeout: Double
    /// Optional cap in seconds on the whole exchange, whatever flows (legacy `timeoutIntervalForResource`); nil for none.
    public var totalTimeout: Double?
    /// Redirect handling for this request.
    public var redirectPolicy: RedirectPolicy
    /// Largest body accepted, in bytes; nil for no limit. Past it (or on a larger `Content-Length`) the transport stops
    /// reading and throws `NetworkError.invalidResponse`, so an untrusted host cannot make the app hold an unbounded body.
    public var maximumBodyBytes: Int?

    /// Creates a request; defaults to a followed GET with the standard timeout.
    public init(
        url: URL,
        method: HTTPMethod = .get,
        headers: HTTPHeaders = [:],
        body: Data? = nil,
        timeout: Double = RequestTimeout.standard,
        totalTimeout: Double? = nil,
        redirectPolicy: RedirectPolicy = .follow,
        maximumBodyBytes: Int? = nil
    ) {
        self.totalTimeout = totalTimeout
        self.maximumBodyBytes = maximumBodyBytes
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
        totalTimeout: Double? = nil,
        redirectPolicy: RedirectPolicy = .follow
    ) -> HTTPRequest {
        HTTPRequest(url: url, headers: headers, timeout: timeout, totalTimeout: totalTimeout, redirectPolicy: redirectPolicy)
    }

    /// A form POST; sets the content type. POSTs are never retried by the transport.
    public static func post(
        _ url: URL,
        form: FormBody,
        headers: HTTPHeaders = [:],
        timeout: Double = RequestTimeout.standard,
        totalTimeout: Double? = nil,
        redirectPolicy: RedirectPolicy = .follow
    ) -> HTTPRequest {
        var headers = headers
        headers["Content-Type"] = FormBody.contentType
        return HTTPRequest(
            url: url, method: .post, headers: headers, body: form.data,
            timeout: timeout, totalTimeout: totalTimeout, redirectPolicy: redirectPolicy
        )
    }
}
