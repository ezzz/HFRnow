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
    /// rebuilt here because its sub-category segment cannot be derived. Redirects are followed, so the response's
    /// final URL tells the page. `anchor` is the message number, added as the `#t<number>` fragment.
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
