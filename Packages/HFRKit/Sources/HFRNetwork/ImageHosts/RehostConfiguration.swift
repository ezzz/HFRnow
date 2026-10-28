import Foundation
/// Where and with which key images are uploaded. Both values are injected (ADR 0007), never written in source.
public struct RehostConfiguration: Sendable, Equatable {
    /// Path of the Chevereto v1 upload endpoint (legacy `ReplyService.swift:1970` @ 2440d79).
    static let uploadPath = "/api/1/upload/"

    /// Base URL of the host, for example the origin of `img3.super-h.fr`.
    public let baseURL: URL
    private let apiKey: String

    /// Validates the injected values; the key never appears in this type's description.
    ///
    /// An empty key throws `.notConfigured` so a build without a key can switch the feature off. The base URL must be
    /// `https`; plain `http` is accepted for a loopback host only, because the key travels in the query string.
    public init(baseURL: URL, apiKey: String) throws(RehostError) {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw .notConfigured }
        guard Self.isAcceptable(baseURL) else { throw .invalidBaseURL }
        self.baseURL = baseURL
        self.apiKey = key
    }

    /// The upload URL with the key as its `key` query item (legacy form `…/api/1/upload/?key=…`).
    func uploadURL() throws(RehostError) -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { throw .invalidBaseURL }
        var path = components.percentEncodedPath
        while path.hasSuffix("/") { path.removeLast() }
        components.percentEncodedPath = path + Self.uploadPath
        components.percentEncodedQuery = "key=" + QueryEncoding.encode(apiKey)
        guard let url = components.url else { throw .invalidBaseURL }
        return url
    }

    /// The key, for redacting it from text a host sends back.
    func redacting(_ text: String) -> String {
        // The raw key and its query form (`+` is `%2B`, hex digits in either case, RFC 3986): a host may echo either.
        text.replacingOccurrences(of: QueryEncoding.encode(apiKey), with: "[key]", options: .caseInsensitive)
            .replacingOccurrences(of: apiKey, with: "[key]")
    }

    private static func isAcceptable(_ url: URL) -> Bool {
        // No userinfo, query or fragment: the base URL is shown in `description` and the key must be the only secret in the query.
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              let host = parts.host?.lowercased(), !host.isEmpty, let scheme = parts.scheme?.lowercased() else { return false }
        if scheme == "https" { return true }
        return scheme == "http" && ["127.0.0.1", "localhost", "::1"].contains(host)
    }
}

extension RehostConfiguration: CustomStringConvertible, CustomDebugStringConvertible {
    /// Shows the base URL only.
    public var description: String { "RehostConfiguration(baseURL: \(baseURL.absoluteString))" }
    /// Same as `description`.
    public var debugDescription: String { description }
}
