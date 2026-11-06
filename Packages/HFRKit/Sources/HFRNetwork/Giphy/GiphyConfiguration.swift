import Foundation
/// Where and with which key Giphy's REST API is called. Both values are injected (ADR 0007), never written in source.
public struct GiphyConfiguration: Sendable, Equatable {
    /// Origin of the API (the captures `T40`/`T41` used `https://api.giphy.com`).
    public let baseURL: URL
    private let apiKey: String

    /// Validates the injected values; the key never appears in this type's description.
    ///
    /// A blank key throws `.notConfigured` so a build without a key switches the feature off. The base URL must be
    /// `https`, or `http` on a loopback host (tests), without userinfo, query or fragment: the key travels in the query.
    public init(baseURL: URL, apiKey: String) throws(GiphyError) {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw .notConfigured }
        guard Self.isAcceptable(baseURL) else { throw .invalidBaseURL }
        self.baseURL = baseURL
        self.apiKey = key
    }

    /// `<base>/v1/gifs/<endpoint>` with `items` then `api_key`, every value percent-encoded.
    func url(endpoint: String, items: [(String, String)]) throws(GiphyError) -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { throw .invalidBaseURL }
        var path = components.percentEncodedPath
        while path.hasSuffix("/") { path.removeLast() }
        components.percentEncodedPath = path + "/v1/gifs/" + endpoint
        components.percentEncodedQuery = (items + [("api_key", apiKey)])
            .map { $0.0 + "=" + QueryEncoding.encode($0.1) }.joined(separator: "&")
        guard let url = components.url else { throw .invalidBaseURL }
        return url
    }

    private static func isAcceptable(_ url: URL) -> Bool {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              let host = parts.host?.lowercased(), !host.isEmpty, let scheme = parts.scheme?.lowercased() else { return false }
        if scheme == "https" { return true }
        return scheme == "http" && ["127.0.0.1", "localhost", "::1"].contains(host)
    }
}

extension GiphyConfiguration: CustomStringConvertible, CustomDebugStringConvertible {
    /// Shows the base URL only.
    public var description: String { "GiphyConfiguration(baseURL: \(baseURL.absoluteString))" }
    /// Same as `description`.
    public var debugDescription: String { description }
}
