import Foundation
import HFRModels
import HFRParsing

/// Which topic page the reader shows, and the message to scroll to.
struct ReaderTarget: Hashable, Sendable {
    /// How the page is requested.
    enum Source: Hashable, Sendable {
        /// `forum2.php` with the topic's category and number (HFR redirects it to the canonical page). The only source since
        /// LOT-137: a canonical path is read by LOT-095's router, which knows its category, and is never fetched as the
        /// link wrote it.
        case topic(TopicID)
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

    /// The target of a forum link, nil when the link is not a topic or private message page of the forum. LOT-095's router
    /// is the only link parser (LOT-137): page and anchor are kept, so a post link opens its page at the post (issue #106),
    /// and a link naming a message lets HFR pick its page (R25). `fallbackTopic` is the topic the caller already knows (a
    /// list row): a canonical path of that same topic number opens it even when its forum segment is not in the catalogue
    /// (#125), because the request is then built from the known topic, never from the link.
    init?(link: String, fallbackTopic: TopicID? = nil) {
        guard let url = Self.forumURL(link) else { return nil }
        switch HFRLinkRoute.route(for: url) {
        case .topic(let routed), .privateMessageThread(let routed):
            self.init(routed)
        default:
            let text = url.absoluteString
            guard let fallbackTopic, let canonical = HFRURL.canonicalTopicPath(in: text), canonical.topic == fallbackTopic.topic
            else { return nil }
            self.init(source: .topic(fallbackTopic), page: canonical.page, anchor: HFRURL.anchorPostNumber(in: text))
        }
    }

    /// The target of a routed topic link: its page, or, when it names a message, no page (HFR serves the message's page).
    init(_ link: HFRTopicLink) {
        if let message = link.numreponse {
            self.init(source: .topic(link.id), anchor: link.scrollTarget, numreponse: message)
        } else {
            self.init(source: .topic(link.id), page: link.page ?? 1, anchor: link.anchorPostNumber)
        }
    }

    /// The same topic at another page, anchor dropped.
    func atPage(_ page: Int) -> ReaderTarget {
        ReaderTarget(source: source, page: page)
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
