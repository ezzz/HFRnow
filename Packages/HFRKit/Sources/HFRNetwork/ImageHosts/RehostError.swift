/// Why an image upload did not produce a hosted image. Never carries the API key, the image or a URL with a query.
public enum RehostError: Error, Sendable, Equatable {
    /// No API key was injected: the feature is off in this build (ADR 0007).
    case notConfigured
    /// The injected base URL is not an `https` URL (or `http` on loopback, for tests) with a host.
    case invalidBaseURL
    /// There is nothing to upload.
    case emptyImage
    /// The exchange failed before an answer (offline, timeout, cancelled).
    case network(NetworkError)
    /// The host answered with a status outside 200-299; `message` is its own explanation, if it sent one.
    case http(statusCode: Int, message: String?)
    /// The host answered 2xx but its payload reports a failure.
    case rejected(statusCode: Int, message: String?)
    /// The answer is not the JSON object the host API returns.
    case invalidResponse
    /// The host confirmed the upload but returned no usable image URL.
    case missingImageURL
}
