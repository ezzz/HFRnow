import Foundation
import HFRModels
import Testing
@testable import HFRParsing

/// `HFRLinkRoute.route(for:)` on the link shapes of the capture corpus (anonymized ids) and on the shapes it must refuse.
@Suite("Link router")
struct HFRLinkRouteTests {
    static let host = "https://forum.hardware.fr"

    static func route(_ link: String) throws -> HFRLinkRoute {
        HFRLinkRoute.route(for: try #require(URL(string: link), "test URL \(link) is valid"))
    }

    static func topic(_ category: Int, _ topic: Int, page: Int?, numreponse: Int? = nil, anchor: Int?) -> HFRTopicLink {
        HFRTopicLink(id: TopicID(category: .forum(category), topic: topic), page: page, numreponse: numreponse, anchorPostNumber: anchor)
    }

    /// Topic list row shape (captures R08-2, R04): `page=1` beside a message number, no fragment.
    static let rowLink = "/forum2.php?config=hfr.inc&cat=13&post=98802&page=1&p=1&sondage=0&owntopic=0&trash=0&trash_post=0&print=0"
        + "&numreponse=56951285&quote_only=0&new=0&nojs=0"
    /// Topic page pager link (captures R21).
    static let pagerLink = "/forum2.php?config=hfr.inc&cat=13&subcat=433&post=28563&page=3&p=1&sondage=0&owntopic=0&trash=0"
        + "&trash_post=0&print=0&numreponse=0&quote_only=0&new=0&nojs=0#bas"

    // MARK: - Topics: page and message are kept on both URL shapes (bug #106)

    @Test("Canonical topic URLs keep category, page and message", arguments: [
        ("/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_2201.htm#t75482227", topic(13, 28563, page: 2201, anchor: 75482227)),
        ("/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_2201.htm", topic(13, 28563, page: 2201, anchor: nil)),
        ("/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_6.htm#bas", topic(13, 28563, page: 6, anchor: nil)),
        ("/hfr/Programmation/Divers-6/hfr-android-sujet_148745_1.htm", topic(10, 148745, page: 1, anchor: nil)),
        ("/hfr/Discussions/slug-sujet_1_2.htm", topic(13, 1, page: 2, anchor: nil)),
        ("/hfr/ia/slug-sujet_7_3.htm#t9", topic(32, 7, page: 3, anchor: 9))
    ])
    func canonicalTopic(path: String, expected: HFRTopicLink) throws {
        #expect(try Self.route(Self.host + path) == .topic(expected))
    }

    @Test("forum2.php keeps category, page and message", arguments: [
        ("/forum2.php?config=hfr.inc&cat=13&post=28563&page=2201#t75482227", topic(13, 28563, page: 2201, anchor: 75482227)),
        ("/forum2.php?config=hfr.inc&amp;cat=13&amp;post=28563&amp;page=2#t5", topic(13, 28563, page: 2, anchor: 5)),
        (pagerLink, topic(13, 28563, page: 3, anchor: nil)),
        // Legacy bookmark link (`Bookmark.m:17`): no page, the message is named twice.
        ("/forum2.php?config=hfr.inc&cat=14&post=115&numreponse=5978240#t5978240",
         topic(14, 115, page: nil, numreponse: 5978240, anchor: 5978240)),
        // The same without the fragment: legacy turned `numreponse` into the anchor (`Common.swift:2672-2686`).
        ("/forum2.php?config=hfr.inc&cat=14&post=115&numreponse=5978240", topic(14, 115, page: nil, numreponse: 5978240, anchor: nil)),
        // Intra-topic search result (HFR-PROTOCOL §7 E28): the page and message are right, the highlighted word is dropped.
        ("/forum2.php?config=hfr.inc&cat=13&post=28563&page=4&word=PIZZA&spseudo=&currentnum=77#t77",
         topic(13, 28563, page: 4, anchor: 77)),
        ("/forum2.php?cat=13&post=28563", topic(13, 28563, page: nil, anchor: nil)),
        // The fragment wins over `numreponse`, as in `searchMatchURL`; the server picks the page then (R25), `page=` is dropped.
        ("/forum2.php?cat=13&post=1&page=2&numreponse=8#t9", topic(13, 1, page: nil, numreponse: 8, anchor: 9)),
        // Row shape of the topic lists: the declared `page=1` is not the page of the message (R25).
        (rowLink, topic(13, 98802, page: nil, numreponse: 56951285, anchor: nil))
    ])
    func forum2Topic(path: String, expected: HFRTopicLink) throws {
        #expect(try Self.route(Self.host + path) == .topic(expected))
    }

    @Test("Private message threads are their own route")
    func privateThread() throws {
        let link = "/forum2.php?config=hfr.inc&cat=prive&post=3207033&page=2&p=1&sondage=0&owntopic=0&trash=0&trash_post=0&print=0"
            + "&numreponse=0&quote_only=0&new=0&nojs=0#t5"
        let expected = HFRTopicLink(id: TopicID(category: .privateMessages, topic: 3207033), page: 2, numreponse: nil, anchorPostNumber: 5)
        #expect(try Self.route(Self.host + link) == .privateMessageThread(expected))
    }

    @Test("A message link is fetchable: the endpoint shape is page 1 plus numreponse, and the scroll target survives")
    func messageLinkKeepsNumreponseAndAnchor() throws {
        guard case .topic(let link) = try Self.route(Self.host + "/forum2.php?cat=13&post=1&page=2&numreponse=8#t9") else {
            Issue.record("a topic link")
            return
        }
        #expect(link.numreponse == 8 && link.anchorPostNumber == 9 && link.scrollTarget == 9)
        guard case .topic(let bare) = try Self.route(Self.host + "/forum2.php?cat=13&post=1&numreponse=8") else {
            Issue.record("a topic link")
            return
        }
        #expect(bare.scrollTarget == 8)
        #expect(bare.page == nil)
    }

    @Test("A bad page= is refused even when numreponse would make the router drop it")
    func badPageWithNumreponse() throws {
        let url = try #require(URL(string: Self.host + "/forum2.php?cat=13&post=1&page=abc&numreponse=8"))
        #expect(HFRLinkRoute.route(for: url) == .external(url))
    }

    @Test("Absolute http links to the forum are routed like https ones (ADR 0006 amendment 1)")
    func httpAndCase() throws {
        let expected = HFRLinkRoute.topic(Self.topic(13, 28563, page: 25, anchor: 29181769))
        let path = "/hfr/Discussions/Cuisine/unique-maison-francaise-sujet_28563_25.htm#t29181769"
        #expect(try Self.route("http://forum.hardware.fr" + path) == expected)
        #expect(try Self.route("HTTPS://Forum.Hardware.FR" + path) == expected)
    }

    // MARK: - Lists

    @Test("Canonical topic lists keep forum, sub-forum and page", arguments: [
        ("/hfr/Discussions/liste_sujet-1.htm", HFRTopicListLink(category: .forum(13), subcategory: nil, page: 1, filter: .all)),
        ("/hfr/Discussions/liste_sujet-500.htm", HFRTopicListLink(category: .forum(13), subcategory: nil, page: 500, filter: .all)),
        ("/hfr/Programmation/Java/liste_sujet-12.htm",
         HFRTopicListLink(category: .forum(10), subcategory: .pathSegment("Java"), page: 12, filter: .all)),
        ("/hfr/Hardware/carte-mere/liste_sujet-1.htm",
         HFRTopicListLink(category: .forum(1), subcategory: .pathSegment("carte-mere"), page: 1, filter: .all))
    ])
    func canonicalList(path: String, expected: HFRTopicListLink) throws {
        #expect(try Self.route(Self.host + path) == .topicList(expected))
    }

    @Test("forum1.php keeps forum, sub-forum, page and filter", arguments: [
        ("/forum1.php?config=hfr.inc&cat=13&page=1&subcat=&owntopic=2",
         HFRTopicListLink(category: .forum(13), subcategory: nil, page: 1, filter: .read)),
        ("/forum1.php?config=hfr.inc&cat=13&page=4&subcat=433&owntopic=3",
         HFRTopicListLink(category: .forum(13), subcategory: .id(433), page: 4, filter: .favorites)),
        ("/forum1.php?config=hfr.inc&cat=25&page=2&subcat=0&sondage=0&owntopic=1&trash=0&trash_post=0&moderation=0&new=0",
         HFRTopicListLink(category: .forum(25), subcategory: nil, page: 2, filter: .flagged)),
        ("/forum1.php?cat=13", HFRTopicListLink(category: .forum(13), subcategory: nil, page: 1, filter: .all))
    ])
    func forum1List(path: String, expected: HFRTopicListLink) throws {
        #expect(try Self.route(Self.host + path) == .topicList(expected))
    }

    @Test("Private message list and favourites")
    func privateListAndFavourites() throws {
        #expect(try Self.route(Self.host + "/forum1.php?config=hfr.inc&cat=prive&page=1") == .privateMessageList(page: 1))
        let pager = "/forum1.php?config=hfr.inc&cat=prive&page=7&subcat=0&sondage=0&owntopic=0&trash=0&trash_post=0&moderation=0"
            + "&new=0&nojs=0&subcatgroup=0"
        #expect(try Self.route(Self.host + pager) == .privateMessageList(page: 7))
        #expect(try Self.route(Self.host + "/forum1f.php?config=hfr.inc&owntopic=3&new=0&nojs=0") == .favorites(filter: .favorites))
        #expect(try Self.route(Self.host + "/forum1f.php?owntopic=1") == .favorites(filter: .flagged))
    }

    // MARK: - Profile, search, home

    @Test("Profiles, search and home")
    func otherRoutes() throws {
        #expect(try Self.route(Self.host + "/hfr/profil-910001.htm") == .profile(userID: 910001))
        #expect(try Self.route(Self.host + "/search.php?config=hardwarefr.inc&cat=&subcat=0") == .search)
        #expect(try Self.route(Self.host + "/") == .home)
        #expect(try Self.route(Self.host) == .home)
    }

    /// Pager link of the search results (capture R50b): repeats `cat` and `trash`.
    static let searchPager = "/forum1.php?config=hfr.inc&cat=13&page=2&subcat=0&sondage=0&owntopic=0&trash=0&trash_post=0&moderation=0"
        + "&new=0&post_cat_list=&trash=0&orderSearch=0&recherches=1&resSearch=200&jour=0&mois=0&annee=0&titre=3"
        + "&search=PIZZA+NAPOLITAINE&pseud=&daterange=2&searchtype=1&searchall=0&cat=13&nojs=0&subcatgroup=0"
    /// First results page (R50b `currentUrl`): no `page`.
    static let searchFirst = "/forum1.php?recherches=1&cat=13&orderSearch=0&config=hfr.inc&pseud=&search=pizza+napolitaine&titre=3"
        + "&jour=&mois=&annee=&resSearch=200&daterange=2&subcat=0&searchtype=1&trash=0&trash_post=0&moderation=0"

    @Test("A page of search results is not a topic list: the known search parameters are kept, repeats dropped")
    func searchResults() throws {
        let rebuilt = Self.searchPager.replacing("&trash=0&orderSearch", with: "&orderSearch").replacing("&cat=13&nojs", with: "&nojs")
        #expect(try Self.route(Self.host + Self.searchPager) == .searchResults(path: rebuilt))
        #expect(try Self.route(Self.host + Self.searchFirst) == .searchResults(path: Self.searchFirst))
    }

    @Test("Search results are rebuilt from an allowlist: other parameters and the fragment are never replayed")
    func searchResultsAllowlist() throws {
        let link = "/forum1.php?config=hfr.inc&cat=13&recherches=1&search=pizza&evil=1&action=delete&hash_check=abc&numreponse=5#t9"
        #expect(try Self.route(Self.host + link) == .searchResults(path: "/forum1.php?config=hfr.inc&cat=13&recherches=1&search=pizza"))
        let amp = "/forum1.php?config=hfr.inc&amp;cat=13&amp;recherches=1&amp;search=a%26b+c"
        #expect(try Self.route(Self.host + amp) == .searchResults(path: "/forum1.php?config=hfr.inc&cat=13&recherches=1&search=a%26b+c"))
        for bad in ["&page=x", "&resSearch=2;3", "&jour=-1", "&jour=%31"] {
            let url = try #require(URL(string: Self.host + "/forum1.php?config=hfr.inc&cat=13&recherches=1&search=a" + bad))
            #expect(HFRLinkRoute.route(for: url) == .external(url), "\(bad)")
        }
    }

    @Test("Paths and shapes match in exact case only", arguments: [
        "/FORUM2.PHP?cat=13&post=1", "/Forum2.php?cat=13&post=1", "/Forum1.php?cat=13", "/FORUM1F.PHP?owntopic=3", "/Search.php",
        "/HFR/Discussions/slug-sujet_1_1.htm", "/hfr/Discussions/slug-SUJET_1_1.htm", "/hfr/Discussions/slug-sujet_1_1.HTM",
        "/hfr/Discussions/LISTE_SUJET-1.htm", "/hfr/Discussions/liste_sujet-1.HTM", "/hfr/PROFIL-1.htm", "/hfr/profil-1.HTM"
    ])
    func exactCase(path: String) throws {
        let url = try #require(URL(string: Self.host + path))
        #expect(HFRLinkRoute.route(for: url) == .external(url))
    }

    // MARK: - Never guessed: unknown shapes and unusable values are external

    @Test("Page, category and filter values that do not parse make the link external, never page 1", arguments: [
        "/forum2.php?config=hfr.inc&cat=13&post=1&page=0", "/forum2.php?config=hfr.inc&cat=13&post=1&page=-1",
        "/forum2.php?config=hfr.inc&cat=13&post=1&page=abc", "/forum2.php?config=hfr.inc&cat=13&post=1&page=2x",
        "/forum2.php?config=hfr.inc&cat=13&post=1&page=99999999999999999999",
        "/forum2.php?config=hfr.inc&cat=13&post=1&numreponse=abc",
        "/forum2.php?config=hfr.inc&cat=13&post=0", "/forum2.php?config=hfr.inc&cat=13", "/forum2.php?config=hfr.inc&post=1",
        "/forum2.php?config=hfr.inc&cat=0&post=1", "/forum2.php?config=hfr.inc&cat=x&post=1",
        "/forum2.php?config=other.inc&cat=13&post=1&page=2",
        "/forum1.php?config=hfr.inc&cat=13&page=0", "/forum1.php?config=hfr.inc&cat=13&subcat=abc",
        "/forum1.php?config=hfr.inc&cat=13&owntopic=4", "/forum1.php?config=hfr.inc&cat=13&owntopic=-1",
        "/forum1.php?config=hfr.inc&cat=13&owntopic=02", "/forum1.php?config=hfr.inc&page=2", "/forum1.php",
        "/forum1f.php", "/forum1f.php?owntopic=0", "/forum1f.php?owntopic=2", "/forum1f.php?owntopic=x"
    ])
    func unusableValues(path: String) throws {
        let url = try #require(URL(string: Self.host + path))
        #expect(HFRLinkRoute.route(for: url) == .external(url))
    }

    @Test("Shapes that are not a plain page, or that no capture or legacy code explains, are external", arguments: [
        // Print view and single-message quote view of a topic (captures R21): not the topic page.
        "/forum2.php?config=hfr.inc&cat=13&post=1&page=1&print=1",
        "/forum2.php?config=hfr.inc&cat=13&post=1&page=1&numreponse=77&quote_only=1",
        "/forum2.php?config=hfr.inc&cat=13&post=1&trash=1",
        // Old shape found in captures R06 and never explained.
        "/forum2.php3?post=1&cat=13",
        "/message.php?config=hfr.inc&cat=13&post=1&numrep=2&ref=1&page=1&p=1&subcat=0&sondage=0&owntopic=0&new=0#formulaire",
        "/user/modo.php?config=hfr.inc&cat=13&post=1&numreponse=2&page=1&ref=1", "/user/addflag.php?config=hfr.inc&cat=13&post=1",
        "/viewbbcode.php?config=hfr.inc&cat=13&numreponse=2", "/profilebdd.php?config=hfr.inc&pseudo=user3",
        "/hfr/recherche/pseudo-user2.htm", "/hfr/Discussions/nouveau_sujet.htm", "/hfr/Discussions/nouveau_sondage.htm",
        "/forum.php?config=hfr.inc&nojs=5", "/?config=hfr.inc", "/#t1", "/rss.php?config=hfr.inc&num=10",
        // Forums the catalogue does not know, and the catalogue is matched exactly (legacy `isEqualToString:`).
        "/hfr/Apple/slug-sujet_1_1.htm", "/hfr/NotAForum/slug-sujet_1_1.htm", "/hfr/NotAForum/liste_sujet-1.htm",
        "/hfr/discussions/liste_sujet-1.htm",
        // Canonical shapes with a page or id that is not a positive integer.
        "/hfr/Discussions/slug-sujet_5_0.htm", "/hfr/Discussions/slug-sujet_0_1.htm", "/hfr/Discussions/liste_sujet-0.htm",
        "/hfr/profil-0.htm", "/hfr/profil-abc.htm", "/hfr/profil-1.htm/x",
        // Encoded slashes cannot create segments, and extra segments are not guessed.
        "/hfr/Discussions%2FCuisine/slug-sujet_1_1.htm", "/hfr/Discussions/a/b/slug-sujet_1_1.htm", "/hfr/slug-sujet_1_1.htm"
    ])
    func unknownShapes(path: String) throws {
        let url = try #require(URL(string: Self.host + path))
        #expect(HFRLinkRoute.route(for: url) == .external(url))
    }

    @Test("The first of a repeated parameter wins, as in HFRURL")
    func repeatedParameter() throws {
        #expect(try Self.route(Self.host + "/forum2.php?cat=13&post=1&page=2&page=3") == .topic(Self.topic(13, 1, page: 2, anchor: nil)))
    }
}
