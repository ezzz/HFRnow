import HFRNetwork
import HFRParsing

/// Why an AQ read failed. Every case means "no information": the caller keeps what it showed, never assumes "none".
public enum AQError: Error, Sendable, Equatable {
    /// The injected base URL is not an acceptable AQ origin (see `AQConfiguration`).
    case invalidBaseURL
    /// A topic number that is not positive.
    case invalidTopicID
    /// The exchange failed (offline, timeout, cancelled, body over the size limit).
    case network(NetworkError)
    /// The host answered a 4xx or 5xx status.
    case http(statusCode: Int)
    /// The host answered a redirect; it is not followed, so requests reach the configured host only.
    case redirected(statusCode: Int)
    /// The body is not the expected document (HTML error page, empty body, the other AQ document).
    case invalidResponse(ParsingError)
}
