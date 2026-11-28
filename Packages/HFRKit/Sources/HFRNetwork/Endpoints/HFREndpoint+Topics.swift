import Foundation
import HFRModels

extension HFREndpoint {
    /// R2: the topic list of a forum (`ObjCForumTopicsLoaderWorker.m:36-89, 128-141`).
    ///
    /// The query is exactly `config, cat, page, subcat (empty), owntopic`, or, with `subcategory` (a sub-forum's numeric
    /// `subcat`), the longer query of `R603d`. Private messages use `privateMessages(page:)`.
    public static func topicList(
        category: CategoryID, subcategory: Int? = nil, filter: TopicListFilter = .all, page: Int = 1
    ) throws -> HTTPRequest {
        try requirePage(page)
        guard let path = ForumCatalogue.topicListPath(categoryID: category, subcategory: subcategory, filter: filter, page: page) else {
            throw NetworkError.invalidRequest(reason: "private messages have their own list")
        }
        return try .get(url(path: path))
    }

    /// R5: one page of a topic (`ObjCTopicPageWorker.m:14-43, 86-94`).
    ///
    /// Always `forum2.php?config=hfr.inc&cat=..&post=..&page=..`, which HFR redirects (301) to the canonical
    /// `/hfr/<forum>[/<sub-category>]/<slug>-sujet_<post>_<page>.htm` (HFR-PROTOCOL §6). The canonical path is never
    /// built from ids, because its sub-category segment cannot be derived; once a page was served, use
    /// `topicPage(topic:page:servedAt:)`. Redirects are followed, so the final URL tells the page. `anchor` is the message
    /// number, added as the `#t<number>` fragment.
    ///
    /// `numreponse` is the shape of a link to a message whose page is not known (R25, `page=1&numreponse=M`): the server
    /// ignores `page` then and redirects to the page holding the message, so pass page 1.
    public static func topicPage(topic: TopicID, page: Int = 1, anchor: Int? = nil, numreponse: Int? = nil) throws -> HTTPRequest {
        try requirePage(page)
        var query = [
            ("config", config), ("cat", topic.category.queryValue), ("post", String(topic.topic)), ("page", String(page))
        ]
        if let numreponse {
            guard numreponse >= 1 else { throw NetworkError.invalidRequest(reason: "numreponse must be 1 or more") }
            query.append(("numreponse", String(numreponse)))
        }
        var request = try HTTPRequest.get(url(path: "/forum2.php", query: query))
        if let anchor, let withFragment = URL(string: request.url.absoluteString + "#t\(anchor)") {
            request.url = withFragment
        }
        return request
    }

    /// R5 asked from a page of the same topic HFR already served (#1394): its canonical path with the page changed, one
    /// round trip instead of the one or two 301 hops `forum2.php` costs, each on a new connection. Legacy changed pages the
    /// same way (`TopicPageURLRouting.replacingPage`, `HFRswift/Swift/Common.swift:2818-2834` @ 87fe0d1c). HFR serves that
    /// path in place (`R298a`'s last hop), redirects a page past the end to the last one (`R24`'s 302) and an outdated slug
    /// to the current one (`R298e`).
    ///
    /// `served` counts only when it is a canonical page of this topic number on the forum origin (`https`, no port, no user
    /// info): any other URL, and a private conversation (served at `forum2.php` in place, `R388a`), gives the `forum2.php`
    /// request of `topicPage(topic:page:)`.
    public static func topicPage(topic: TopicID, page: Int, servedAt served: URL?) throws -> HTTPRequest {
        try requirePage(page)
        guard topic.category != .privateMessages, let served, let stem = canonicalStem(of: served, topic: topic.topic) else {
            return try topicPage(topic: topic, page: page)
        }
        return try .get(url(path: "\(stem)_\(page).htm"))
    }

    /// The path of `served` up to `sujet_<topic>`, when `served` is a canonical topic page of the forum origin
    /// (`/hfr/<forum>[/<sub-category>]/<slug>-sujet_<topic>_<page>.htm`, HFR-PROTOCOL R5), written as HFR serves it: the
    /// whole path, lower-case `sujet` and `.htm` as in every capture, the topic number as written, no `.` or `..` segment
    /// (encoded or not).
    static func canonicalStem(of served: URL, topic: Int) -> String? {
        guard served.scheme?.lowercased() == "https", served.host()?.lowercased() == forumHostName, served.port == nil,
              served.user() == nil, served.password() == nil else { return nil }
        let path = served.path(percentEncoded: true)
        let hasDotSegment = path.split(separator: "/").contains { segment in
            let decoded = String(segment).removingPercentEncoding ?? String(segment)
            return decoded == "." || decoded == ".."
        }
        guard !hasDotSegment, let match = path.wholeMatch(of: canonicalPagePattern), match.output.2 == String(topic) else {
            return nil
        }
        return String(match.output.1)
    }

    /// The forum's host name, as `host` names it.
    static let forumHostName = "forum.hardware.fr"

    // `Regex` is not `Sendable`; this literal captures only `Substring`s and is compiled once by the runtime.
    nonisolated(unsafe) private static let canonicalPagePattern =
        /(\/hfr\/[^\/]+\/(?:[^\/]+\/)?[^\/]+-sujet_([0-9]+))_[0-9]+\.htm/

    /// R5 for a known message: the page holding it, with its `#t<numreponse>` anchor.
    public static func topicPage(post: PostID, page: Int) throws -> HTTPRequest {
        try topicPage(topic: post.topic, page: page, anchor: post.numreponse)
    }

    /// The quote view of one message (`quote_only=1`, #1039): the posts that quote message `numreponse` of `topic`, in place, with no
    /// pager (capture `R126a`, HFR-PROTOCOL §6c « Batch A »). Built in the exact shape of the capture, empty parameters
    /// included and in HFR's order, because that is the only shape seen; `subcategory` is the link's `subcat=` (HFR writes it empty
    /// for a forum without sub-categories).
    public static func quotingMessages(topic: TopicID, subcategory: Int?, numreponse: Int) throws -> HTTPRequest {
        guard numreponse >= 1 else { throw NetworkError.invalidRequest(reason: "numreponse must be 1 or more") }
        let query = [
            ("config", config), ("cat", topic.category.queryValue), ("subcat", subcategory.map(String.init) ?? ""),
            ("post", String(topic.topic)), ("page", "1"), ("p", "1"), ("sondage", ""), ("owntopic", ""), ("trash", ""),
            ("trash_post", ""), ("print", ""), ("numreponse", String(numreponse)), ("quote_only", "1"), ("new", "0"), ("nojs", "0")
        ]
        return try HTTPRequest.get(url(path: "/forum2.php", query: query))
    }
}
