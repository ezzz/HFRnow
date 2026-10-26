import Foundation

extension HFRURL {
    /// Forum-relative form (`/path?query#fragment`) of a link read from a page, or nil when it must not be followed.
    ///
    /// List models keep relative paths (LOT-010), and the app requests them with the account session, so every path
    /// a list parser emits goes through here (LESSONS 37): a path starting with a single `/` is kept as is; anything else
    /// is resolved by `absolute(_:relativeTo:)` and kept only when it is `https` on `forum.hardware.fr` without user info
    /// or a port other than 443. `&amp;` is decoded; an empty link, `javascript:`, another host, a protocol-relative
    /// `//host` or `/\host` link, and `http://forum.hardware.fr:80/` give nil.
    static func forumRelativePath(_ raw: String) -> String? {
        let link = decodingAmpersands(String(raw.trimmingHTMLWhitespace))
        guard !link.isEmpty, !link.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) else {
            return nil
        }
        if link.hasPrefix("/") {
            return isNetworkPathReference(link) ? nil : link
        }
        guard
            let url = absolute(link),
            url.scheme == "https",
            url.host(percentEncoded: false) == forumHost,
            url.port == nil || url.port == 443,
            let components = URLComponents(url: url, resolvingAgainstBaseURL: true)
        else { return nil }
        // `https://forum.hardware.fr//evil.example/x` has a forum host but a path that, once the origin is dropped,
        // reads as `//evil.example/x`: refuse it, the result must hold the same invariant as a direct path.
        var path = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
        guard !isNetworkPathReference(path) else { return nil }
        if let query = components.percentEncodedQuery {
            path += "?" + query
        }
        if let fragment = components.percentEncodedFragment {
            path += "#" + fragment
        }
        return path
    }

    /// `//host…` or `/\host…`: resolved against the forum, browsers and `URL` read the second form's authority too.
    private static func isNetworkPathReference(_ path: String) -> Bool {
        let second = path.dropFirst().first
        return path.hasPrefix("/") && (second == "/" || second == "\\")
    }
}
