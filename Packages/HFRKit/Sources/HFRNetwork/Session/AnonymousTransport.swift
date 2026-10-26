import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A transport that never sends nor stores cookies, for anonymous prefetch and images.
///
/// Any authenticated topic GET marks the account's flags read (HFR-PROTOCOL §7, E25), so background prefetch must
/// not go through an `HFRSession`. Image hosts must not receive forum cookies either (E26). Besides disabling the
/// session's cookie handling, it drops any explicit `Cookie` header a caller put on the request.
public struct AnonymousTransport: HTTPTransport {
    private let transport: URLSessionTransport

    /// Creates a transport on its own ephemeral, cookie-less `URLSession`.
    public init() {
        self.init(configuration: .ephemeral)
    }

    /// Same, from a base configuration (tests use one without proxy); its cookie settings are always overridden.
    init(configuration: URLSessionConfiguration) {
        transport = URLSessionTransport(session: URLSession(configuration: Self.cookieless(configuration)))
    }

    /// Sends `request` without any cookie.
    public func perform(_ request: HTTPRequest) async throws(NetworkError) -> HTTPResponse {
        var request = request
        request.headers["Cookie"] = nil
        return try await transport.perform(request)
    }

    /// `configuration` with cookies disabled both ways and no cache or credential store.
    static func cookieless(_ configuration: URLSessionConfiguration) -> URLSessionConfiguration {
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        return configuration
    }
}
