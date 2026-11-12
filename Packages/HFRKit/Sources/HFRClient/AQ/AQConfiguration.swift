import Foundation

/// Where the AQ ("Alerte Qualitay") service lives. The base URL is injected (LOT-071 R2), never written in source.
///
/// Legacy hard-coded `https://aq.super-h.fr` (`AQPlusView.swift:39`, `MessagesView.swift:327` @ 2440d79).
public struct AQConfiguration: Sendable, Equatable {
    /// Path of the RSS feed (`AQPlusView.swift:39` @ 2440d79, capture `T01`).
    static let feedPath = "/rss.php"
    /// Path of the per-topic listing (`MessagesView.swift:327` @ 2440d79, capture `T02`).
    static let alertsPath = "/api/getAlertesByTopic.php"

    /// Path of the create (`MessagesView.swift:340-376` @ 2440d79, captures `T50`, `T51`).
    static let createPath = "/api/addAlerte.php"

    /// Origin of the AQ host, for example `https://aq.super-h.fr`.
    public let baseURL: URL

    /// Validates the injected base URL.
    ///
    /// It must be `https` (both captures were served over https), or `http` on a loopback host for tests; no userinfo,
    /// query or fragment. A `hardware.fr` host is refused: AQ is a third party and the forum is not its host.
    public init(baseURL: URL) throws(AQError) {
        guard Self.isAcceptable(baseURL) else { throw .invalidBaseURL }
        self.baseURL = baseURL
    }

    /// The RSS feed URL.
    func feedURL() throws(AQError) -> URL {
        try url(path: Self.feedPath, query: nil)
    }

    /// The listing URL of `topicID` (`?topic_id=<topic>`, `T02`).
    func alertsURL(topicID: Int) throws(AQError) -> URL {
        guard topicID > 0 else { throw .invalidTopicID }
        return try url(path: Self.alertsPath, query: "topic_id=\(topicID)")
    }

    /// The create URL.
    func createURL() throws(AQError) -> URL {
        try url(path: Self.createPath, query: nil)
    }

    private func url(path: String, query: String?) throws(AQError) -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { throw .invalidBaseURL }
        var base = components.percentEncodedPath
        while base.hasSuffix("/") { base.removeLast() }
        components.percentEncodedPath = base + path
        components.percentEncodedQuery = query
        guard let url = components.url else { throw .invalidBaseURL }
        return url
    }

    private static func isAcceptable(_ url: URL) -> Bool {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              var host = parts.host?.lowercased(), !host.isEmpty, let scheme = parts.scheme?.lowercased() else { return false }
        if host.hasSuffix(".") { host.removeLast() }
        if host == "hardware.fr" || host.hasSuffix(".hardware.fr") { return false }
        if scheme == "https" { return true }
        return scheme == "http" && ["127.0.0.1", "localhost", "::1", "[::1]"].contains(host)
    }
}
