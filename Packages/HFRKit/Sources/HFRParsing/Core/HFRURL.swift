import Foundation
import HFRModels

/// URL helpers for the links HFR puts in its pages (HFR-PROTOCOL §1 R2–R5, §4).
///
/// Inputs are raw `href` values as found in HTML, possibly relative, possibly still holding `&amp;`.
/// Query parameters are matched by **exact name** (`page`, never `subpage`); numbers must be positive ASCII integers.
public enum HFRURL {
    /// Host of the forum (`Classes/k.m:37-40`).
    public static let forumHost = "forum.hardware.fr"

    /// Root every relative forum link is resolved against.
    public static let base: URL = {
        guard let url = URL(string: "https://forum.hardware.fr/") else {
            preconditionFailure("The forum base URL literal is valid")
        }
        return url
    }()

    /// Replaces `&amp;` by `&`, the only entity legacy code decodes in links (`ObjCMessageActionsBuilder.m:73`).
    public static func decodingAmpersands(_ raw: String) -> String {
        raw.replacing("&amp;", with: "&")
    }

    /// Absolute `https`/`http` URL for a raw link, or nil when it is empty or uses any other scheme.
    ///
    /// `//host/x` gets `https:`; other relative forms are resolved against `page` (the forum root by default).
    /// ASCII tabs and newlines are removed first, as browsers do, so `java\nscript:` cannot slip through;
    /// URLs with user info (`https://forum.hardware.fr@evil.example/`) are refused; hosts are lowercased;
    /// `http` links to the forum without an explicit port are upgraded to `https` (ADR 0006 amendment 1),
    /// while an explicit port is kept and blocks the upgrade (https on another port is not known to work).
    public static func absolute(_ raw: String, relativeTo page: URL = base) -> URL? {
        let stripped = String(String.UnicodeScalarView(raw.unicodeScalars.filter { !["\t", "\n", "\r"].contains($0) }))
        var candidate = decodingAmpersands(stripped.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !candidate.isEmpty else { return nil }
        if candidate.hasPrefix("//") {
            candidate = "https:" + candidate
        }
        guard
            let resolved = URL(string: candidate, relativeTo: page)?.absoluteURL,
            var components = URLComponents(url: resolved, resolvingAgainstBaseURL: true),
            let scheme = components.scheme?.lowercased(), scheme == "https" || scheme == "http",
            let host = components.host?.lowercased(), !host.isEmpty,
            components.user == nil, components.password == nil
        else { return nil }
        components.host = host
        components.scheme = host == forumHost && components.port == nil ? "https" : scheme
        return components.url
    }

    /// Value of the first query parameter called exactly `name`, percent-decoded; nil when absent.
    ///
    /// `+` is kept as is, not turned into a space: legacy code read values the same way (`NSURLComponents`,
    /// `ObjCTopicPageWorker.m:17-22`) and HFR's own links carry digits, ids and slugs only.
    public static func queryValue(named name: String, in raw: String) -> String? {
        guard let query = Parts(decodingAmpersands(raw)).query else { return nil }
        for item in query.split(separator: "&") {
            let pair = item.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair[0] == name else { continue }
            let value = pair.count > 1 ? String(pair[1]) : ""
            return value.removingPercentEncoding ?? value
        }
        return nil
    }

    /// Page number of a list or topic link: `page=` first, then the canonical `sujet_<post>_<page>.htm`,
    /// then the older `_<page>.htm` ending (`ObjCTopicPageWorker.m:14-43`, `ObjCTopicListParser.m:9-38`).
    public static func page(in raw: String) -> Int? {
        if let page = queryValue(named: "page", in: raw).flatMap(positiveInteger) {
            return page
        }
        if let canonical = canonicalTopicPath(in: raw) {
            return canonical.page
        }
        let path = Parts(decodingAmpersands(raw)).path
        return path.firstMatch(of: legacyPagePattern).flatMap { positiveInteger($0.output.1) }
    }

    /// Topic and page of a canonical topic URL `…-sujet_<post>_<page>.htm` (HFR-PROTOCOL R5); nil for other shapes.
    public static func canonicalTopicPath(in raw: String) -> CanonicalTopicPath? {
        let path = Parts(decodingAmpersands(raw)).path
        guard
            let match = canonicalMatch(in: path),
            let topic = positiveInteger(match.topic),
            let page = positiveInteger(match.page)
        else { return nil }
        return CanonicalTopicPath(topic: topic, page: page)
    }

    /// Category of a link (`cat=13`, `cat=prive`); nil when absent or invalid. Canonical paths carry a slug, not the id.
    public static func category(in raw: String) -> CategoryID? {
        queryValue(named: "cat", in: raw).flatMap(CategoryID.init(queryValue:))
    }

    /// Topic number of a link: `post=` first, then the canonical path.
    public static func topicNumber(in raw: String) -> Int? {
        queryValue(named: "post", in: raw).flatMap(positiveInteger) ?? canonicalTopicPath(in: raw)?.topic
    }

    /// Topic identity when the link carries both `cat=` and a topic number.
    public static func topicID(in raw: String) -> TopicID? {
        guard let category = category(in: raw), let topic = topicNumber(in: raw) else { return nil }
        return TopicID(category: category, topic: topic)
    }

    /// Message number from `numreponse=`; `0` means "none" on HFR links and gives nil (`Common.swift:2549-2553`).
    public static func numreponse(in raw: String) -> Int? {
        queryValue(named: "numreponse", in: raw).flatMap(positiveInteger)
    }

    /// Message number from a `#t<numreponse>` fragment, the only reliable post id in quote links
    /// (redface2 research §4.3 E20).
    public static func anchorPostNumber(in raw: String) -> Int? {
        guard
            let fragment = Parts(raw).fragment,
            let match = fragment.wholeMatch(of: anchorPattern)
        else { return nil }
        return positiveInteger(match.output.1)
    }

    /// The link without its fragment (`#t123`, `#bas`); unchanged when there is none.
    public static func removingAnchor(_ raw: String) -> String {
        guard let hash = raw.firstIndex(of: "#") else { return raw }
        return String(raw[..<hash])
    }

    /// The link pointing at `page` instead, fragment dropped; nil when `page < 1`.
    ///
    /// Replaces the `page=` parameter, else the page of a canonical or older `_<page>.htm` path,
    /// else appends `page=` (`Common.swift:2510-2541`, `Topic.m:73-84`).
    public static func replacingPage(in raw: String, with page: Int) -> String? {
        guard page >= 1 else { return nil }
        var link = removingAnchor(decodingAmpersands(raw))
        let parts = Parts(link)
        // `parts` slices `link` before any mutation, so their indices are valid for the single replacement below.
        if let item = parts.query?.split(separator: "&").first(where: { item in item.prefix { $0 != "=" } == "page" }) {
            link.replaceSubrange(item.startIndex..<item.endIndex, with: "page=\(page)")
            return link
        }
        if let match = canonicalMatch(in: parts.path) {
            link.replaceSubrange(match.page.startIndex..<match.page.endIndex, with: String(page))
            return link
        }
        if let match = parts.path.firstMatch(of: legacyPagePattern) {
            link.replaceSubrange(match.output.1.startIndex..<match.output.1.endIndex, with: String(page))
            return link
        }
        let separator = parts.query == nil ? "?" : (link.hasSuffix("&") || link.hasSuffix("?") ? "" : "&")
        return link + separator + "page=\(page)"
    }

    // MARK: - Implementation

    /// Topic and page digits of a whole path `/hfr/<cat>[/<sub>]/<slug>-sujet_<post>_<page>.htm`, as slices of `path`.
    private static func canonicalMatch(in path: Substring) -> (topic: Substring, page: Substring)? {
        guard let match = path.firstMatch(of: canonicalPattern) else { return nil }
        return (match.output.1, match.output.2)
    }

    // `Regex` is not `Sendable` (its output type could hold non-Sendable captures). These literals capture
    // only `Substring`s and the compiled program is initialised atomically by the runtime, so sharing is safe.
    nonisolated(unsafe) private static let canonicalPattern =
        /^\/hfr\/[^\/]+\/(?:[^\/]+\/)?[^\/]+-sujet_([0-9]+)_([0-9]+)\.htm$/.ignoresCase()

    /// Older `…_<page>.htm` ending kept from legacy code (unverified shape, HFR-PROTOCOL R5).
    nonisolated(unsafe) private static let legacyPagePattern = /_([0-9]+)\.htm$/.ignoresCase()

    /// `t<numreponse>` fragment.
    nonisolated(unsafe) private static let anchorPattern = /t([0-9]+)/

    /// A positive integer written with ASCII digits only.
    static func positiveInteger(_ text: some StringProtocol) -> Int? {
        guard !text.isEmpty, text.utf8.allSatisfy({ (48...57).contains($0) }), let value = Int(text), value > 0 else {
            return nil
        }
        return value
    }

    /// Path, query and fragment of a raw link, as slices of the same string so indices can be reused.
    /// The path excludes the scheme and authority of an absolute or protocol-relative link.
    private struct Parts {
        let path: Substring
        let query: Substring?
        let fragment: Substring?

        init(_ link: String) {
            let hash = link.firstIndex(of: "#")
            var beforeFragment = link[..<(hash ?? link.endIndex)]
            fragment = hash.map { link[link.index(after: $0)...] }
            if let authorityStart = Self.authorityStart(of: beforeFragment) {
                let rest = beforeFragment[authorityStart...]
                beforeFragment = rest[(rest.firstIndex { $0 == "/" || $0 == "?" } ?? rest.endIndex)...]
            }
            if let mark = beforeFragment.firstIndex(of: "?") {
                path = beforeFragment[..<mark]
                query = beforeFragment[beforeFragment.index(after: mark)...]
            } else {
                path = beforeFragment
                query = nil
            }
        }

        /// Index after `scheme://` or a leading `//`, when the link has an authority.
        private static func authorityStart(of link: Substring) -> Substring.Index? {
            if link.hasPrefix("//") {
                return link.index(link.startIndex, offsetBy: 2)
            }
            guard let separator = link.firstRange(of: "://") else { return nil }
            let scheme = link[..<separator.lowerBound]
            let isScheme = scheme.first?.isLetter == true
                && scheme.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "+-.".contains($0)) }
            return isScheme ? separator.upperBound : nil
        }
    }
}
