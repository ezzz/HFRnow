import Foundation
import HFRModels

/// Where a forum link leads, decided from the URL alone (no request, no page parsing).
///
/// Only `forum.hardware.fr` links are routed (LESSONS 37, 43): any other host, scheme, user info or explicit port,
/// and every shape this type does not know, is `.external` and must never be requested with the account session.
/// A shape is known only when it appears in a capture or in legacy code (`docs/lots/LOT-095-link-router.md`).
public enum HFRLinkRoute: Sendable, Hashable {
    /// The forum home page (`/`).
    case home
    /// A public topic, from `forum2.php` or the canonical `/hfr/<cat>/[<sub>/]<slug>-sujet_<post>_<page>.htm`.
    case topic(HFRTopicLink)
    /// A private message thread (`forum2.php` with `cat=prive`).
    case privateMessageThread(HFRTopicLink)
    /// A topic list of a forum or sub-forum.
    case topicList(HFRTopicListLink)
    /// The private message list (`forum1.php` with `cat=prive`), at the given page (one-based).
    case privateMessageList(page: Int)
    /// The favourites page (`forum1f.php`); the filter is `.flagged` or `.favorites`.
    case favorites(filter: TopicListFilter)
    /// A public profile (`/hfr/profil-<id>.htm`).
    case profile(userID: Int)
    /// The search form (`/search.php`).
    case search
    /// A page of global search results; the forum-relative path is rebuilt from the known search parameters only
    /// (R50b), since the terms live in the query (HFR-PROTOCOL S2).
    case searchResults(path: String)
    /// Anything else: foreign hosts, unknown shapes, links with a value that does not parse.
    case external(URL)
}

/// The topic a link points at, with the page and message it names (`nil` when the link does not say).
public struct HFRTopicLink: Sendable, Hashable {
    /// Category and topic number.
    public var id: TopicID
    /// One-based page, or `nil` when the link names none or names a message: the server then picks the page.
    ///
    /// Request it with page 1 and `numreponse` (`HFREndpoint.topicPage(topic:page:numreponse:)`, R25), never by guessing.
    public var page: Int?
    /// Message number of `numreponse=` (non-zero): the server redirects to the page that holds it (R25). Kept apart
    /// from `anchorPostNumber`, which is what the link's fragment says (`numreponse=8#t9` keeps both).
    public var numreponse: Int?
    /// Message number from the `#t<numreponse>` fragment, to scroll to; `nil` when the fragment names none.
    public var anchorPostNumber: Int?

    /// The message to scroll to once the page is shown: the fragment's, else `numreponse`.
    public var scrollTarget: Int? { anchorPostNumber ?? numreponse }

    /// Creates a topic link.
    public init(id: TopicID, page: Int?, numreponse: Int? = nil, anchorPostNumber: Int?) {
        self.id = id
        self.page = page
        self.numreponse = numreponse
        self.anchorPostNumber = anchorPostNumber
    }
}

/// A topic list location.
public struct HFRTopicListLink: Sendable, Hashable {
    /// Forum the list belongs to.
    public var category: CategoryID
    /// Sub-forum, or `nil` for the whole forum.
    public var subcategory: HFRSubcategory?
    /// One-based page (1 when the link has none: a list has no other meaningful default).
    public var page: Int
    /// Topic filter (`owntopic`); `.all` for canonical list paths, which cannot carry one.
    public var filter: TopicListFilter

    /// Creates a topic list link.
    public init(category: CategoryID, subcategory: HFRSubcategory?, page: Int, filter: TopicListFilter) {
        self.category = category
        self.subcategory = subcategory
        self.page = page
        self.filter = filter
    }
}

/// A sub-forum as a link names it: the two link shapes do not carry the same thing.
public enum HFRSubcategory: Sendable, Hashable {
    /// The numeric `subcat` of `forum1.php`.
    case id(Int)
    /// The path segment of a canonical list URL (`Java` in `/hfr/Programmation/Java/liste_sujet-1.htm`); the numeric id is
    /// not derivable from it.
    case pathSegment(String)
}
