import Foundation
import HFRModels

extension HFRLinkRoute {
    /// Routes a link, or returns `.external(url)` when it is not a known `forum.hardware.fr` shape.
    ///
    /// Page and message are kept: `page=` or the `_<page>.htm` ending, `#t<numreponse>` (HFR-PROTOCOL R5, §4).
    /// A page value that is present but not a positive ASCII integer makes the link `.external` instead of falling back
    /// to page 1. `&amp;` is decoded as in `HFRURL`; for repeated parameters the first one wins, as in `HFRURL`.
    public static func route(for url: URL) -> HFRLinkRoute {
        guard let target = Target(url), let route = try? route(for: target) else { return .external(url) }
        return route
    }

    private static func route(for target: Target) throws -> HFRLinkRoute {
        // Exact case: no capture shows `/FORUM2.PHP` or `/HFR/…`, so they are not guessed to be the same pages.
        switch target.path {
        case "", "/":
            guard target.query == nil, target.fragment == nil else { throw Refused() }
            return .home
        case "/forum2.php": return try topic(target)
        case "/forum1.php": return try list(target)
        case "/forum1f.php": return try favorites(target)
        case "/search.php": return .search
        default: return try canonical(target)
        }
    }

    // MARK: - forum2.php

    private static func topic(_ target: Target) throws -> HFRLinkRoute {
        try target.requireForumConfig()
        try target.requirePlainTopicView()
        guard let topic = try target.positive("post") else { throw Refused() }
        let category = try target.category()
        let numreponse = try target.numreponse()
        // Validated even when it is dropped below: an unusable `page=` makes the link external.
        let page = try target.positive("page")
        let link = HFRTopicLink(
            id: TopicID(category: category, topic: topic),
            // With a message number the server picks the page itself and ignores `page=` (R25: `page=1&numreponse=M`
            // answers a redirect to the page holding M): keeping the link's `page=` would open page 1 by mistake.
            page: numreponse == nil ? page : nil,
            numreponse: numreponse,
            anchorPostNumber: target.anchorPostNumber
        )
        return category == .privateMessages ? .privateMessageThread(link) : .topic(link)
    }

    // MARK: - forum1.php, forum1f.php

    private static func list(_ target: Target) throws -> HFRLinkRoute {
        try target.requireForumConfig()
        let category = try target.category()
        if target.has("recherches") || target.has("search") {
            return .searchResults(path: try target.searchResultsPath())
        }
        let page = try target.positive("page") ?? 1
        if category == .privateMessages {
            return .privateMessageList(page: page)
        }
        return .topicList(HFRTopicListLink(
            category: category,
            subcategory: try target.subcategory(),
            page: page,
            filter: try target.filter(allowed: [.all, .flagged, .read, .favorites])
        ))
    }

    private static func favorites(_ target: Target) throws -> HFRLinkRoute {
        try target.requireForumConfig()
        guard target.has("owntopic") else { throw Refused() }
        return .favorites(filter: try target.filter(allowed: [.flagged, .favorites]))
    }

    // MARK: - /hfr/... canonical paths

    private static func canonical(_ target: Target) throws -> HFRLinkRoute {
        let path = target.path
        if let match = path.wholeMatch(of: profilePattern), let userID = HFRURL.positiveInteger(match.output.1) {
            return .profile(userID: userID)
        }
        if let match = path.wholeMatch(of: topicPattern) {
            // The category segment is matched exactly, as legacy did: an unknown or re-cased forum is not guessed.
            guard
                let category = ForumCatalogue.categoryID(forPath: "/hfr/\(match.output.1)/liste_sujet-1.htm"),
                let topic = HFRURL.positiveInteger(match.output.2),
                let page = HFRURL.positiveInteger(match.output.3)
            else { throw Refused() }
            return .topic(HFRTopicLink(
                id: TopicID(category: category, topic: topic), page: page, anchorPostNumber: target.anchorPostNumber
            ))
        }
        if let match = path.wholeMatch(of: listPattern) {
            guard
                let category = ForumCatalogue.categoryID(forPath: "/hfr/\(match.output.1)/liste_sujet-1.htm"),
                let page = HFRURL.positiveInteger(match.output.3)
            else { throw Refused() }
            return .topicList(HFRTopicListLink(
                category: category,
                subcategory: match.output.2.map { .pathSegment(String($0)) },
                page: page,
                filter: .all
            ))
        }
        throw Refused()
    }

    // `Regex` is not `Sendable`; these literals capture only `Substring`s (same reasoning as `HFRURL`).
    nonisolated(unsafe) private static let profilePattern = /\/hfr\/profil-([0-9]+)\.htm/
    nonisolated(unsafe) private static let topicPattern =
        /\/hfr\/([^\/]+)\/(?:[^\/]+\/)?[^\/]+-sujet_([0-9]+)_([0-9]+)\.htm/
    nonisolated(unsafe) private static let listPattern =
        /\/hfr\/([^\/]+)\/(?:([^\/]+)\/)?liste_sujet-([0-9]+)\.htm/
}
