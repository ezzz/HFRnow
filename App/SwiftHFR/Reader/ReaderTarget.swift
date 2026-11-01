import Foundation
import HFRModels
import HFRParsing

/// Which topic page the reader shows, and the message to scroll to.
struct ReaderTarget: Hashable, Sendable {
    /// How the page is requested.
    enum Source: Hashable, Sendable {
        /// `forum2.php` with the topic's category and number (HFR redirects it to the canonical page).
        case topic(TopicID)
        /// A forum-relative link without a category (a canonical `…-sujet_<post>_<page>.htm` path), fetched as is.
        case path(String)
    }

    var source: Source
    /// Page to show, 1-based.
    var page: Int
    /// Message number to scroll to once the page is shown (the `#t<numreponse>` anchor), nil for the top.
    var anchor: Int?
    /// The message of a `numreponse=M` link (bookmarks, AQ, permalinks): HFR picks the page that holds it and redirects
    /// there (`R25`), so the link's `page=` is not that page and `page` is only a placeholder (issue #106).
    var numreponse: Int?

    /// Creates a target; pages below 1 become 1.
    init(source: Source, page: Int = 1, anchor: Int? = nil, numreponse: Int? = nil) {
        self.source = source
        self.page = max(1, page)
        self.anchor = anchor
        self.numreponse = numreponse
    }

    /// The page a topic row opens: the flag link (last read position, with its anchor) when the row has one, else the
    /// row's own link (`TopicOpenPolicy.defaultDecision`, legacy `HFRswift/Swift/Common.swift:2593-2635` on `master`).
    /// Favourites rows already hold their resume link in `path` (LOT-024).
    init?(opening topic: TopicSummary) {
        let link = topic.flagPath ?? topic.path
        if let target = ReaderTarget(link: link, fallbackTopic: topic.topicID) {
            self = target
        } else if let topicID = topic.topicID {
            self.init(source: .topic(topicID), page: topic.currentPage ?? 1)
        } else {
            return nil
        }
    }

    /// The target of a forum link (`/forum2.php?…&post=…&page=…#t…`, or a canonical topic path), nil when the link is not
    /// a topic page of the forum. Page and anchor are kept, so a post link opens its page at the post (issue #106).
    init?(link: String, fallbackTopic: TopicID? = nil) {
        guard let url = Self.forumURL(link) else { return nil }
        let text = url.absoluteString
        let anchor = HFRURL.anchorPostNumber(in: text)
        if let topicID = HFRURL.topicID(in: text) {
            // LOT-095's router drops `page=` when the link names a message: HFR then serves the message's page (R25).
            if case .topic(let routed) = HFRLinkRoute.route(for: url), routed.id == topicID, let message = routed.numreponse {
                self.init(source: .topic(topicID), anchor: routed.scrollTarget, numreponse: message)
            } else {
                self.init(source: .topic(topicID), page: HFRURL.page(in: text) ?? 1, anchor: anchor)
            }
        } else if let canonical = HFRURL.canonicalTopicPath(in: text) {
            if let fallbackTopic, fallbackTopic.topic == canonical.topic {
                self.init(source: .topic(fallbackTopic), page: canonical.page, anchor: anchor)
            } else {
                // Only the path is kept: a canonical topic URL needs no query, and the session GET must not carry one the
                // link's author chose.
                self.init(source: .path(url.path(percentEncoded: true)), page: canonical.page, anchor: anchor)
            }
        } else {
            return nil
        }
    }

    /// The same topic at another page, anchor dropped.
    func atPage(_ page: Int) -> ReaderTarget {
        switch source {
        case .topic:
            return ReaderTarget(source: source, page: page)
        case .path(let path):
            let moved = HFRURL.replacingPage(in: path, with: page) ?? path
            return ReaderTarget(source: .path(moved), page: page)
        }
    }

    /// `link` as an `https` URL of the forum host on the default port; nil for anything else (another host, an explicit
    /// port, user info). Links the reader fetches with the session must stay on the forum origin (LESSONS 37, 43).
    static func forumURL(_ link: String) -> URL? {
        guard let resolved = HFRURL.absolute(link), resolved.host() == HFRURL.forumHost,
              var components = URLComponents(url: resolved, resolvingAgainstBaseURL: false),
              components.port == nil else { return nil }
        components.scheme = "https"
        return components.url
    }
}
