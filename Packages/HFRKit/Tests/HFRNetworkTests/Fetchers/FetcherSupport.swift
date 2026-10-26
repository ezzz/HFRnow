import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import HFRNetwork

/// Sends forum requests to a loopback server, keeping path and query, so real redirects can be exercised.
struct RewritingTransport: HTTPTransport {
    let base: URL
    private let inner: URLSessionTransport

    init(base: URL) {
        self.base = base
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        inner = URLSessionTransport(session: URLSession(configuration: configuration))
    }

    func perform(_ request: HTTPRequest) async throws(NetworkError) -> HTTPResponse {
        var request = request
        guard var parts = URLComponents(url: request.url, resolvingAgainstBaseURL: false),
              let target = URLComponents(url: base, resolvingAgainstBaseURL: false) else { throw .invalidRequest(reason: "test") }
        parts.scheme = target.scheme
        parts.host = target.host
        parts.port = target.port
        guard let rewritten = parts.url else { throw .invalidRequest(reason: "test") }
        request.url = rewritten
        return try await inner.perform(request)
    }
}

/// A scripted answer for `MockTransport`.
func okResponse(_ path: String = "/", body: String = "", contentType: String = "text/html; charset=utf-8") -> HTTPResponse {
    HTTPResponse(
        statusCode: 200, headers: ["Content-Type": contentType],
        url: URL(string: "https://forum.hardware.fr" + path) ?? URL(fileURLWithPath: "/"), body: Data(body.utf8)
    )
}
