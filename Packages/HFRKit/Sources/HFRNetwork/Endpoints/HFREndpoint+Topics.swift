import Foundation
import HFRModels

extension HFREndpoint {
    /// R2: the topic list of a forum (`ObjCForumTopicsLoaderWorker.m:36-89, 128-141`).
    ///
    /// The query is exactly `config, cat, page, subcat (empty), owntopic`. Private messages use `privateMessages(page:)`.
    public static func topicList(category: CategoryID, filter: TopicListFilter = .all, page: Int = 1) throws -> HTTPRequest {
        try requirePage(page)
        guard let path = ForumCatalogue.topicListPath(categoryID: category, filter: filter, page: page) else {
            throw NetworkError.invalidRequest(reason: "private messages have their own list")
        }
        return try .get(url(path: path))
    }

    /// R5: one page of a topic (`ObjCTopicPageWorker.m:14-43, 86-94`).
    ///
    /// Always `forum2.php?config=hfr.inc&cat=..&post=..&page=..`, which HFR redirects (301) to the canonical
    /// `/hfr/<forum>[/<sub-category>]/<slug>-sujet_<post>_<page>.htm` (HFR-PROTOCOL §6). The canonical path is never
    /// rebuilt here because its sub-category segment cannot be derived. Redirects are followed, so the response's
    /// final URL tells the page. `anchor` is the message number (`numreponse`), added as the `#t<number>` fragment.
    public static func topicPage(topic: TopicID, page: Int = 1, anchor: Int? = nil) throws -> HTTPRequest {
        try requirePage(page)
        var request = try HTTPRequest.get(url(path: "/forum2.php", query: [
            ("config", config), ("cat", topic.category.queryValue), ("post", String(topic.topic)), ("page", String(page))
        ]))
        if let anchor, let withFragment = URL(string: request.url.absoluteString + "#t\(anchor)") {
            request.url = withFragment
        }
        return request
    }

    /// R5 for a known message: the page holding it, with its `#t<numreponse>` anchor.
    public static func topicPage(post: PostID, page: Int) throws -> HTTPRequest {
        try topicPage(topic: post.topic, page: page, anchor: post.numreponse)
    }
}
