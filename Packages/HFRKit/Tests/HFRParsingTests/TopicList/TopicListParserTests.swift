import Foundation
import HFRModels
import Testing
@testable import HFRParsing

/// Behaviour of the topic list parser on the LOT-001 captures, beyond the oracle comparison.
@Suite("Topic list parser")
struct TopicListParserTests {
    // MARK: - Rows

    @Test("Polls are found on the live icon (LOT-002 RC2.3: 14 on R04, 16 on R06, 3 on R27-list)", arguments: [
        ("R04-list-cat13-p1-anon", "/hfr/Discussions/liste_sujet-1.htm", 14),
        ("R06-list-subcat-cuisine-anon", "/hfr/Discussions/Cuisine/liste_sujet-1.htm", 16),
        ("R27-list-list-programmation-anon", "/hfr/Programmation/liste_sujet-1.htm", 3)
    ])
    func pollRows(capture: String, pageURL: String, polls: Int) throws {
        let page = try TopicListParser.parse(Fixture.capture(capture), pageURL: pageURL)
        #expect(page.topics.filter(\.isPoll).count == polls)
    }

    @Test("Anonymous rows: canonical paths, plain-text starter, every row marked unread, catalogue category")
    func anonymousRow() throws {
        let page = try TopicListParser.parse(Fixture.capture("R04-list-cat13-p1-anon"), pageURL: "/hfr/Discussions/liste_sujet-1.htm")
        let row = try #require(page.topics.first)
        #expect(row.title == "Message important : user9 nous a quittés")
        #expect(row.path == "/hfr/Discussions/message-important-quittes-sujet_121557_1.htm")
        #expect(row.topicID == TopicID(category: .forum(13), topic: 121_557))
        #expect(row.starterOrInterlocutors == "user3")
        #expect(row.pageCount == 84)
        #expect(row.repliesCount == 3350)
        #expect(row.isSticky)
        #expect(row.lastPost?.author == "user4")
        #expect(row.lastPost?.path == "/hfr/Discussions/message-important-quittes-sujet_121557_84.htm#bas")
        #expect(page.topics.allSatisfy { $0.readState == .unread })
        #expect(page.topics.allSatisfy { $0.flag == nil && $0.flagPath == nil && $0.currentPage == nil })
    }

    @Test("Last post date is the Paris wall-clock time of the row")
    func lastPostDate() throws {
        let page = try TopicListParser.parse(Fixture.capture("R04-list-cat13-p1-anon"), pageURL: "/hfr/Discussions/liste_sujet-1.htm")
        // "24-10-2026 à 12:44" in Paris (UTC+2 before the 25 October change) is 10:44 UTC.
        #expect(page.topics.first?.lastPost?.date == (try? Date("2026-10-24T10:44:00Z", strategy: .iso8601)))
    }

    @Test("Pseudos keep the U+200B HFR inserts after the 10th character (LOT-002 RC2.6)")
    func zeroWidthSpaceIsKept() throws {
        let page = try TopicListParser.parse(Fixture.capture("R04-list-cat13-p1-anon"), pageURL: "/hfr/Discussions/liste_sujet-1.htm")
        #expect(page.topics[2].starterOrInterlocutors == "user7\u{200B}")
    }

    @Test("Logged-in flagged row: forum2.php links, red flag, resume page, profile link starter")
    func flaggedRow() throws {
        let url = "/forum1.php?config=hfr.inc&cat=13&page=1&subcat=&owntopic=2"
        let page = try TopicListParser.parse(Fixture.capture("R08-2-list-cat13-owntopic2"), pageURL: url)
        let row = try #require(page.topics.first)
        #expect(page.topics.count == 1)
        #expect(row.topicID == TopicID(category: .forum(13), topic: 28_563))
        #expect(row.flag == .red)
        #expect(row.currentPage == 2)
        #expect(row.flagPath?.contains("&post=28563&page=2&") == true)
        #expect(row.flagPath?.hasSuffix("#t3204775") == true)
        #expect(row.starterOrInterlocutors == "user3\u{200B}")
        #expect(row.readState == .unread)
    }

    @Test("MP rows keep the `[non lu]` marker in the title for LOT-023; group threads name no interlocutor")
    func privateMessageRows() throws {
        let page = try TopicListParser.parse(
            Fixture.capture("R13u1-mp-list-recipient-unread"),
            pageURL: "/forum1.php?config=hfr.inc&cat=prive&page=1"
        )
        let group = try #require(page.topics.first { $0.topicID?.topic == 3_197_250 })
        #expect(group.title == "[non lu] Private subject")
        #expect(group.starterOrInterlocutors == "Interlocuteurs multiples")
        #expect(group.topicID?.category == .privateMessages)
        #expect(group.readState == .unread)   // closedbp.gif, alt="On"
        #expect(page.categoryID == .privateMessages)
        #expect(page.topics.filter { $0.readState == .unread }.count == 10)
    }

    @Test("MP read state: `closedp.gif` Off is read, `closedbp.gif` On after marking unread (W18)")
    func privateMessageReadState() throws {
        let url = "/forum1.php?config=hfr.inc&cat=prive&page=1"
        #expect(try TopicListParser.parse(Fixture.capture("R13a-mp-list"), pageURL: url).topics.first?.readState == .read)
        let marked = try TopicListParser.parse(Fixture.capture("R13b-mp-list-after-mark-unread"), pageURL: url)
        #expect(marked.topics.first?.readState == .unread)
    }

    @Test("Search rows: title link only, matching message and trimmed snippet")
    func searchRow() throws {
        let page = try TopicListParser.parse(Fixture.capture("R50b-search-results-no-cookie"), pageURL: Self.searchURL)
        let row = try #require(page.topics.first)
        #expect(row.title == "[TU] Lyon - 6000 pages de vélo et de météo")
        #expect(row.topicID == TopicID(category: .forum(13), topic: 32_554))
        #expect(row.searchHit?.postPath.contains("&post=32554&") == true)
        #expect(row.searchHit?.postPath.contains("&numreponse=75456630&") == true)
        #expect(row.searchHit?.snippet.hasPrefix("Tiens pour recentrer sur la pizza") == true)
        #expect(row.searchHit?.snippet.hasSuffix("[...]") == true)
        #expect(page.topics.allSatisfy { $0.searchHit != nil })
    }

    // MARK: - Page

    @Test("Pager window: last is the last linked page, not the forum's page count (LOT-002 RC2.1)")
    func pagerWindow() throws {
        let page = try TopicListParser.parse(Fixture.capture("R05b-list-cat13-p500-anon"), pageURL: "/hfr/Discussions/liste_sujet-500.htm")
        #expect(page.navigation == PageNavigation(
            current: 500,
            first: 1,
            last: 700,
            firstPath: "/hfr/Discussions/liste_sujet-1.htm",
            lastPath: "/hfr/Discussions/liste_sujet-700.htm",
            nextPath: "/hfr/Discussions/liste_sujet-501.htm",
            previousPath: "/hfr/Discussions/liste_sujet-499.htm"
        ))
    }

    @Test("The current page comes from the pager; an absolute forum URL is reduced to its path")
    func currentPageFromThePager() throws {
        let html = try Fixture.capture("R05a-list-cat13-p12-anon")
        let relative = try TopicListParser.parse(html, pageURL: "/hfr/Discussions/liste_sujet-12.htm")
        let absolute = try TopicListParser.parse(html, pageURL: "https://forum.hardware.fr/hfr/Discussions/liste_sujet-12.htm")
        #expect(absolute == relative)
        // A URL naming another page does not change the page the HTML shows.
        let mislabelled = try TopicListParser.parse(html, pageURL: "/hfr/Discussions/liste_sujet-3.htm")
        #expect(mislabelled.navigation.current == 12)
        // A URL off the forum is not echoed as a path.
        let foreignURL = "https://example.invalid/liste_sujet-1.htm"
        let foreign = try TopicListParser.parse(Fixture.capture("R04-list-cat13-p1-anon"), pageURL: foreignURL)
        #expect(foreign.navigation.current == 1)
        #expect(foreign.navigation.firstPath == nil)
    }

    @Test("Search results: the page number does not come from the URL's last digit (LOT-002 RC2.7)")
    func searchPageNumber() throws {
        let html = try Fixture.capture("R50b-search-results-no-cookie")
        let page = try TopicListParser.parse(html, pageURL: Self.searchURL.replacing("moderation=0", with: "moderation=7"))
        #expect(page.navigation.current == 1)
        #expect(page.navigation.last == 2)
        #expect(page.navigation.nextPath == page.navigation.lastPath)
    }

    @Test("Unread private messages in the header of a logged-in list", arguments: [
        ("P03f-list-owntopic2-after-delflag", "/forum1.php?config=hfr.inc&cat=13&page=1&subcat=&owntopic=2", 1 as Int?),
        ("R08-2-list-cat13-owntopic2", "/forum1.php?config=hfr.inc&cat=13&page=1&subcat=&owntopic=2", 0),
        ("R04-list-cat13-p1-anon", "/hfr/Discussions/liste_sujet-1.htm", nil),
        ("R13a-mp-list", "/forum1.php?config=hfr.inc&cat=prive&page=1", nil)
    ])
    func unreadPrivateMessages(capture: String, pageURL: String, unread: Int?) throws {
        #expect(try TopicListParser.parse(Fixture.capture(capture), pageURL: pageURL).unreadPrivateMessages == unread)
    }

    @Test("Logged-in lists expose the four filter tabs and the category")
    func tabs() throws {
        let page = try TopicListParser.parse(
            Fixture.capture("R08-2-list-cat13-owntopic2"),
            pageURL: "/forum1.php?config=hfr.inc&cat=13&page=1&subcat=&owntopic=2"
        )
        #expect(page.tabs.all == "/hfr/Discussions/liste_sujet-1.htm")
        #expect(page.tabs.favorites?.contains("&owntopic=3&") == true)
        #expect(page.tabs.flagBlue?.contains("&owntopic=1&") == true)
        #expect(page.tabs.flagRed?.contains("&owntopic=2&") == true)
        #expect(page.categoryID == .forum(13))
        #expect(page.newTopicPath == "/hfr/Discussions/nouveau_sujet.htm")
    }

    @Test("A `.hop` message page is an empty page with the message (LOT-002 RC2.4)", arguments: [
        ("R08-1-list-cat13-owntopic1-empty", "/forum1.php?config=hfr.inc&cat=13&page=1&subcat=&owntopic=1",
         "Aucun sujet auquel vous avez participé n'est connu"),
        ("R08-3-list-cat13-owntopic3-empty", "/forum1.php?config=hfr.inc&cat=13&page=1&subcat=&owntopic=3",
         "Aucun favori n'est repertorié"),
        ("R50c-search-no-result-no-cookie", searchURL, "Désolé, aucune réponse n'a été trouvée !")
    ])
    func messagePage(capture: String, pageURL: String, message: String) throws {
        let page = try TopicListParser.parse(Fixture.capture(capture), pageURL: pageURL)
        #expect(page == TopicListPage(notice: message))
    }

    @Test("An empty MP list is an empty page without a message")
    func emptyPrivateMessageList() throws {
        let page = try TopicListParser.parse(
            Fixture.capture("R13c-mp-list-empty-after-delete"),
            pageURL: "/forum1.php?config=hfr.inc&cat=prive&page=1"
        )
        #expect(page.topics.isEmpty)
        #expect(page.notice == nil)
        #expect(page.categoryID == .privateMessages)
        #expect(page.navigation == PageNavigation())
    }

    @Test("A page that is neither a list nor an HFR message is malformed")
    func neitherListNorMessage() throws {
        // The smiley search answer (R53a) is a bare text fragment: no list body, no `.hop`.
        #expect(throws: ListPageFailure.malformed("page without list body or message")) {
            try TopicListParser.parse(Fixture.capture("R53a-smiley-search-no-result"), pageURL: "/")
        }
    }

    @Test("A page with another body id (topic page, reply form) is not a list", arguments: [
        "R20-topic-p1-anon", "R40a-reply-form-logged-in"
    ])
    func otherPageIsNotAList(capture: String) throws {
        #expect(throws: ListPageFailure.malformed("page without list body or message")) {
            try TopicListParser.parse(Fixture.capture(capture), pageURL: "/")
        }
    }

    @Test("A near-miss body id is not a list", arguments: ["not_topics_listing", "x__topics_listing", "topics_listing__x"])
    func nearMissBodyID(id: String) throws {
        let html = try Fixture.capture("R04-list-cat13-p1-anon")
            .replacing(#"<body id="category__topics_listing__listing_topic""#, with: #"<body id="\#(id)""#)
        #expect(throws: ListPageFailure.malformed("page without list body or message")) {
            try TopicListParser.parse(html, pageURL: "/hfr/Discussions/liste_sujet-1.htm")
        }
    }

    // MARK: - Hostile input

    @Test("A row whose title link is not a forum path is skipped, and no foreign link is emitted")
    func hostileLinks() throws {
        let url = "/hfr/Discussions/liste_sujet-1.htm"
        let original = try Fixture.capture("R04-list-cat13-p1-anon")
        // Adversarial edits of a real page: a script title link, and a last-page link to another host.
        let hostile = original
            .replacing(#"href="/hfr/Discussions/message-important-quittes-sujet_121557_1.htm""#, with: #"href="javascript:alert(1)""#)
            .replacing(#"href="/hfr/Discussions/Viepratique/kimarc-kimousses-hommage-sujet_121565_6.htm""#,
                       with: #"href="https://evil.example/kimarc-sujet_121565_6.htm""#)
        let page = try TopicListParser.parse(hostile, pageURL: url)
        let reference = try TopicListParser.parse(original, pageURL: url)
        #expect(page.topics.count == reference.topics.count - 1)
        #expect(page.topics.allSatisfy { !$0.path.contains("javascript") })
        let row = try #require(page.topics.first)
        #expect(row.path == "/hfr/Discussions/Viepratique/kimarc-kimousses-hommage-sujet_121565_1.htm")
        #expect(row.lastPagePath == row.path)   // the refused link counts as absent: one page, as legacy without a link
        #expect(row.pageCount == 1)
    }

    @Test("A page whose rows are all unreadable is malformed, not an empty list")
    func allRowsUnreadable() throws {
        // In-memory edit of a real page: no row keeps its title cell.
        let html = try Fixture.capture("R04-list-cat13-p1-anon").replacing("sujetCase3", with: "sujetCaseX")
        #expect(throws: ListPageFailure.malformed("55 rows, none readable")) {
            try TopicListParser.parse(html, pageURL: "/hfr/Discussions/liste_sujet-1.htm")
        }
    }

    @Test("A `.hop` page served for the MP list is a login wall: an empty MP list keeps the list body (R13c)")
    func privateMessagesMessagePageIsNotAuthenticated() throws {
        // R08-1's page as is; only the URL it is said to come from changes.
        let html = try Fixture.capture("R08-1-list-cat13-owntopic1-empty")
        #expect(throws: ListPageFailure.notAuthenticated("Aucun sujet auquel vous avez participé n'est connu")) {
            try TopicListParser.parse(html, pageURL: "/forum1.php?config=hfr.inc&cat=prive&page=1")
        }
        #expect(throws: ListPageFailure.notAuthenticated("Aucun sujet auquel vous avez participé n'est connu")) {
            try TopicListParser.parse(html, pageURL: "https://forum.hardware.fr/forum1.php?config=hfr.inc&cat=prive&page=1")
        }
    }

    static let searchURL = "/forum1.php?recherches=1&cat=13&orderSearch=0&config=hfr.inc&pseud=&search=pizza+napolitaine&titre=3"
        + "&jour=&mois=&annee=&resSearch=200&daterange=2&subcat=0&searchtype=1&trash=0&trash_post=0&moderation=0"
}
