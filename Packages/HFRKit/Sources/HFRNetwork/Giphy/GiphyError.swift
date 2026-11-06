/// Why a Giphy request did not produce a page of GIFs. Never carries the API key or a URL with a query.
public enum GiphyError: Error, Sendable, Equatable {
    /// No API key was injected: the feature is off in this build (ADR 0007).
    case notConfigured
    /// The injected base URL is not an `https` URL (or `http` on loopback, for tests) with a host.
    case invalidBaseURL
    /// The search text is empty once trimmed: nothing is sent.
    case emptyQuery
    /// The exchange failed before an answer (offline, timeout, cancelled).
    case network(NetworkError)
    /// Giphy answered with a status outside 200-299, a redirect included (it is never followed).
    case http(statusCode: Int)
    /// The answer is not the `{data, meta, pagination}` envelope with a `data` array.
    case invalidResponse
}
