import Foundation
/// Searches and lists trending GIFs through Giphy's public REST API.
///
/// Replaces the closed Giphy SDK of legacy (`HFRswiftApp.swift:9, 20` and the picker `AnswerView.swift:2286-2335` @ 2440d79,
/// rating R at `:2305`): no SDK, no new package. The wire shape comes from the captures `T40`/`T41` (LOT-098).
///
/// Every request is a GET on the injected host with the key and the search text as its only data. No cookie is sent (the
/// default transport is `AnonymousTransport`) and a redirect is not followed, so the key never reaches another host.
public struct GiphyClient: Sendable {
    /// Total time limit of a request, in seconds.
    public static let timeout: Double = 15
    /// Largest answer read, in bytes: 50 items of the captured shape are about 450 KB.
    public static let maximumResponseBytes = 2_097_152
    /// Items per page when the caller gives none (Giphy's own default is not captured, so the client states one).
    public static let defaultLimit = 25
    /// Upper bound of `limit`; larger values are clamped (the captures used 3).
    public static let maximumLimit = 50

    private let configuration: GiphyConfiguration
    private let transport: any HTTPTransport

    /// Creates a client; the transport defaults to the cookie-less one.
    public init(configuration: GiphyConfiguration, transport: any HTTPTransport = AnonymousTransport()) {
        self.configuration = configuration
        self.transport = transport
    }

    /// Searches GIFs for `query` (`/v1/gifs/search`, capture `T40`). Only the trimmed text is sent.
    public func search(
        _ query: String, limit: Int = GiphyClient.defaultLimit, offset: Int = 0, rating: GiphyRating = .restricted
    ) async throws(GiphyError) -> GiphyPage {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw .emptyQuery }
        return try await fetch(request(endpoint: "search", extra: [("q", text)], limit: limit, offset: offset, rating: rating))
    }

    /// Lists the trending GIFs (`/v1/gifs/trending`, capture `T41`).
    public func trending(
        limit: Int = GiphyClient.defaultLimit, offset: Int = 0, rating: GiphyRating = .restricted
    ) async throws(GiphyError) -> GiphyPage {
        try await fetch(request(endpoint: "trending", extra: [], limit: limit, offset: offset, rating: rating))
    }

    /// The request as plain data, so a test can check the policy (host, no cookie, no redirect) without any network.
    func request(
        endpoint: String, extra: [(String, String)], limit: Int, offset: Int, rating: GiphyRating
    ) throws(GiphyError) -> HTTPRequest {
        let items = extra + [
            ("limit", String(min(max(limit, 1), Self.maximumLimit))),
            ("offset", String(max(offset, 0))),
            ("rating", rating.rawValue)
        ]
        return HTTPRequest(
            url: try configuration.url(endpoint: endpoint, items: items), method: .get, headers: ["Accept": "application/json"],
            timeout: Self.timeout, redirectPolicy: .doNotFollow, maximumBodyBytes: Self.maximumResponseBytes
        )
    }

    private func fetch(_ request: HTTPRequest) async throws(GiphyError) -> GiphyPage {
        let response: HTTPResponse
        do {
            response = try await transport.perform(request)
        } catch {
            throw .network(Self.sanitized(error))
        }
        guard (200...299).contains(response.statusCode) else { throw .http(statusCode: response.statusCode) }
        guard let page = GiphyResponse.decode(response.body) else { throw .invalidResponse }
        return page
    }

    /// The request URL carries the key in its query and a transport's `reason` is free text: neither may reach the caller.
    private static func sanitized(_ error: NetworkError) -> NetworkError {
        switch error {
        case let .httpStatus(code, url):
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.query = nil
            components?.user = nil
            components?.password = nil
            return .httpStatus(code: code, url: components?.url ?? url.deletingLastPathComponent())
        case .invalidRequest:
            return .invalidRequest(reason: "giphy request refused")
        default:
            return error
        }
    }
}
