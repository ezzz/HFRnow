import Foundation
/// Sends HTTP requests. Implemented by `URLSessionTransport` and `MockTransport`.
public protocol HTTPTransport: Sendable {
    /// Performs the exchange and returns the answer whatever its status; use `send(_:)` unless you need 4xx/5xx bodies.
    func perform(_ request: HTTPRequest) async throws(NetworkError) -> HTTPResponse
}

extension HTTPTransport {
    /// Performs the exchange and maps 4xx/5xx to `NetworkError.httpStatus`; 3xx is returned (see `RedirectPolicy`).
    public func send(_ request: HTTPRequest) async throws(NetworkError) -> HTTPResponse {
        try await perform(request).validated()
    }
}
