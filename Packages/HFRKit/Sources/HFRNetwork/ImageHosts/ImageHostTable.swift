import Foundation
/// The host adapter table: per-host rules for fetching images, and the request builder that applies them.
///
/// Hosts are recognised by the parsed host of the URL at a label boundary, never by a substring of the text
/// (`reho.st.evil.example` and `notreho.st` are not `reho.st`).
public struct ImageHostTable: Sendable, Equatable {
    /// The `Referer` legacy sent to `reho.st` (`PhotoViewerNetworkRequestFactory`, no trailing slash).
    public static let forumReferer = "https://forum.hardware.fr"

    /// The rules SwiftHFR ships with. Each cites its source in LOT-056's spec.
    public static let standard = ImageHostTable(rules: [
        ImageHostRule(
            host: "reho.st", referer: forumReferer, servesExtensionlessImages: true,
            thumbnailRewrite: .pathPrefix(prefix: "/thumb/", replacement: "/")
        ),
        ImageHostRule(
            host: "img3.super-h.fr", includesSubdomains: false, servesExtensionlessImages: true,
            thumbnailRewrite: .fileNameMarker(pathPrefix: "/images/", marker: ".th.")
        ),
        ImageHostRule(
            host: "rehost.diberie.com", includesSubdomains: false, servesExtensionlessImages: true,
            thumbnailRewrite: .pathPrefix(prefix: "/Picture/Get/t/", replacement: "/Picture/Get/f/")
        ),
        // Hosts whose every reference in the captures R20, R21 and R22a is `http://` (LOT-071).
        ImageHostRule(host: "hostingpics.net", observedHTTPOnly: true),
        ImageHostRule(host: "casimages.com", observedHTTPOnly: true),
        ImageHostRule(host: "free.fr", observedHTTPOnly: true),
        ImageHostRule(host: "photorapide.com", observedHTTPOnly: true),
        ImageHostRule(host: "camif.fr", observedHTTPOnly: true),
        ImageHostRule(host: "hn.org", observedHTTPOnly: true)
    ])

    /// Rules in priority order: the first that matches a host wins.
    public var rules: [ImageHostRule]

    /// Creates a table.
    public init(rules: [ImageHostRule]) {
        self.rules = rules
    }

    /// The rule for the host of `url`, if any. A URL that is not `http(s)` or has no host matches nothing.
    public func rule(for url: URL) -> ImageHostRule? {
        guard let host = Self.normalizedHost(of: url) else { return nil }
        return rules.first { $0.matches(host) }
    }

    /// A cookie-less GET for an image URL: the host's `Referer` if its rule has one, none otherwise (LOT-071 R3).
    ///
    /// Send it through `AnonymousTransport`; nothing here adds a cookie, and the scheme is never rewritten.
    public func request(for url: URL, timeout: Double = RequestTimeout.standard) throws(NetworkError) -> HTTPRequest {
        guard Self.normalizedHost(of: url) != nil else {
            throw .invalidRequest(reason: "image URL is not an absolute http(s) URL")
        }
        var headers = HTTPHeaders()
        if let referer = rule(for: url)?.referer { headers["Referer"] = referer }
        return .get(url, headers: headers, timeout: timeout)
    }

    /// The full-size image for a thumbnail URL of a host with a rewrite rule; any other URL is returned unchanged.
    public func fullSizeURL(for url: URL) -> URL {
        guard let rewrite = rule(for: url)?.thumbnailRewrite,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        let path = components.percentEncodedPath
        let rewritten: String
        switch rewrite {
        case let .pathPrefix(old, replacement):
            guard path.hasPrefix(old) else { return url }
            rewritten = replacement + path.dropFirst(old.count)
        case let .fileNameMarker(prefix, marker):
            guard path.hasPrefix(prefix), let slash = path.lastIndex(of: "/") else { return url }
            let name = path[path.index(after: slash)...]
            guard name.contains(marker) else { return url }
            rewritten = String(path[...slash]) + name.replacingOccurrences(of: marker, with: ".")
        }
        // Foundation's setter traps on a bad percent escape, and a rule is data (a custom one may hold a lone `%`).
        guard Self.isValidEncodedPath(rewritten) else { return url }
        components.percentEncodedPath = rewritten
        return components.url ?? url
    }

    /// True when the host's image URLs have no file extension (so the extension test cannot be used on them).
    public func servesExtensionlessImages(_ url: URL) -> Bool {
        rule(for: url)?.servesExtensionlessImages ?? false
    }

    /// True when `path` only holds characters RFC 3986 allows in a path and every `%` starts two hex digits.
    ///
    /// It does not decode: `%E9` (Latin-1, not UTF-8) is a valid escape that HFR-era hosts use.
    static func isValidEncodedPath(_ path: String) -> Bool {
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~!$&'()*+,;=:@/")
        let hex = Set("0123456789abcdefABCDEF")
        var chars = path.makeIterator()
        while let char = chars.next() {
            if char == "%" {
                guard let first = chars.next(), let second = chars.next(), hex.contains(first), hex.contains(second) else { return false }
            } else if !allowed.contains(char) {
                return false
            }
        }
        return true
    }

    /// Lower-case host without trailing dot for an `http(s)` URL, `nil` otherwise.
    static func normalizedHost(of url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              var host = url.host?.lowercased(), !host.isEmpty else { return nil }
        if host.hasSuffix(".") { host.removeLast() }
        return host.isEmpty ? nil : host
    }
}
