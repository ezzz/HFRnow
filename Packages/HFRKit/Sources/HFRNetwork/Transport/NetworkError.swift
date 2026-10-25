import Foundation
/// Typed failure of an HTTP exchange. Never carries bodies, cookies or query strings.
public enum NetworkError: Error, Sendable, Equatable {
    /// The request cannot be sent (for example a non-HTTP URL).
    case invalidRequest(reason: String)
    /// The server answered with a status of 400 or more (legacy ignored the status).
    case httpStatus(code: Int, url: URL)
    /// No data arrived within the request timeout.
    case timedOut
    /// The device has no usable connection.
    case offline
    /// The surrounding task was cancelled before the exchange completed.
    case cancelled
    /// The answer was not an HTTP response.
    case invalidResponse
    /// Any other transport failure; `code` is the `URLError` code, kept free of URLs.
    case transport(code: Int)
    /// A scripted `MockTransport` ran out of replies (tests only).
    case unscripted
}
