import Foundation
/// An HTTP answer as plain data.
public struct HTTPResponse: Sendable, Equatable {
    /// Status code of the final answer.
    public var statusCode: Int
    /// Response headers.
    public var headers: HTTPHeaders
    /// URL that produced this answer, after any followed redirects.
    public var url: URL
    /// Raw body.
    public var body: Data

    /// Creates a response.
    public init(statusCode: Int, headers: HTTPHeaders = [:], url: URL, body: Data = Data()) {
        self.statusCode = statusCode
        self.headers = headers
        self.url = url
        self.body = body
    }

    /// True for 301, 302, 303, 307 and 308.
    public var isRedirect: Bool { [301, 302, 303, 307, 308].contains(statusCode) }

    /// `Location` resolved against `url` (HFR sends relative locations), if present and valid.
    public var redirectLocation: URL? {
        guard let location = headers["Location"], !location.isEmpty else { return nil }
        return URL(string: location, relativeTo: url)?.absoluteURL
    }

    /// Body decoded using the `Content-Type` charset, then a `<meta>` hint, then UTF-8 with fallbacks.
    public func decodedText() -> DecodedText {
        TextDecoding.decode(body, contentType: headers["Content-Type"])
    }

    /// Throws `NetworkError.httpStatus` for 4xx and 5xx; returns self otherwise.
    public func validated() throws(NetworkError) -> HTTPResponse {
        if statusCode >= 400 { throw .httpStatus(code: statusCode, url: url) }
        return self
    }
}
