import Foundation
import HFRModels
@testable import SwiftHFR
import Testing

/// Which page a row or a link opens (issue #106: a post link opens its page at the post, never page 1).
struct ReaderTargetTests {
    private let flagLink = "/forum2.php?config=hfr.inc&amp;cat=13&amp;subcat=433&amp;post=28563&amp;page=1&amp;p=1&amp;sondage=0"
        + "&amp;owntopic=3&amp;trash=0&amp;trash_post=0&amp;print=0&amp;numreponse=0&amp;quote_only=0&amp;new=0&amp;nojs=0#t2666649"

    @Test func aForum2LinkKeepsTopicPageAndPost() throws {
        let link = flagLink.replacing("page=1&", with: "page=2201&")
        let target = try #require(ReaderTarget(link: link))
        #expect(target.source == .topic(readerTopic))
        #expect(target.page == 2201)
        #expect(target.anchor == 2666649)
    }

    /// `R25`'s request: page 1 plus the message, which HFR answers with a 301 to `…sujet_28563_1100.htm#t39971312`.
    private static let messageLink = "https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=13&post=28563&page=1&numreponse=39971312"

    @Test(arguments: [
        messageLink,
        // A legacy bookmark (`Classes/Bookmark.m:17`): no `page=`, the message both as `numreponse` and as anchor.
        "/forum2.php?config=hfr.inc&cat=13&post=28563&numreponse=39971312#t39971312"
    ])
    func aMessageLinkLetsHFRPickThePage(_ link: String) throws {
        let target = try #require(ReaderTarget(link: link))
        #expect(target.source == .topic(readerTopic))
        #expect(target.numreponse == 39971312)
        #expect(target.anchor == 39971312)
        // Another page of the topic is an ordinary page again.
        #expect(target.atPage(3) == ReaderTarget(source: .topic(readerTopic), page: 3))
    }

    @Test func aFlagLinkNamesNoMessage() throws {
        // `numreponse=0` means none (LOT-095): the flag link keeps its page and anchor.
        let target = try #require(ReaderTarget(link: flagLink))
        #expect(target.numreponse == nil)
        #expect(target.page == 1)
        #expect(target.anchor == 2666649)
    }

    @Test func aCanonicalLinkKeepsPageAndPost() throws {
        // LOT-137: the router reads the forum segment, so the link opens its topic (`forum2.php`), not the path it wrote.
        let link = "http://forum.hardware.fr/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_1353.htm#t44795902"
        let target = try #require(ReaderTarget(link: link))
        #expect(target == ReaderTarget(source: .topic(readerTopic), page: 1353, anchor: 44795902))
        // A known topic does not change what the router read.
        let other = try #require(ReaderTarget(link: link, fallbackTopic: TopicID(category: .forum(5), topic: 1)))
        #expect(other == target)
    }

    /// A forum the catalogue lacks (#125): the router leaves the link alone, but a row of that very topic still opens it,
    /// from the topic the row names.
    @Test func anUncataloguedForumOpensOnlyAsTheKnownTopic() throws {
        let link = "/hfr/NotAForum/pizza-maison-sujet_28563_7.htm#t701"
        #expect(ReaderTarget(link: link) == nil)
        let known = TopicID(category: .forum(99), topic: 28563)
        #expect(ReaderTarget(link: link, fallbackTopic: known) == ReaderTarget(source: .topic(known), page: 7, anchor: 701))
        #expect(ReaderTarget(link: link, fallbackTopic: TopicID(category: .forum(99), topic: 1)) == nil)
        // A canonical-looking name outside the path is not a page.
        #expect(ReaderTarget(link: "/hfr/NotAForum/x.htm?a=pizza-sujet_28563_7.htm", fallbackTopic: known) == nil)
    }

    /// LOT-095 follow-up: links the router does not route as a topic page are not opened in the reader with the session.
    @Test(arguments: [
        // An answer link of the composer.
        "/message.php?config=hfr.inc&cat=13&post=28563&page=2#formulaire",
        // A single-message view and a print view.
        "/forum2.php?config=hfr.inc&cat=13&post=28563&page=2&quote_only=1",
        "/forum2.php?config=hfr.inc&cat=13&post=28563&page=2&print=1",
        // An unusable page is refused, never read as page 1.
        "/forum2.php?config=hfr.inc&cat=13&post=28563&page=abc",
        "/forum2.php?config=hfr.inc&cat=13&post=28563&page=0",
        // A list and a profile are not topic pages.
        "/forum1.php?config=hfr.inc&cat=13",
        "/hfr/profil-12345.htm"
    ])
    func linksTheRouterDoesNotOpenAsATopicAreRefused(_ link: String) {
        #expect(ReaderTarget(link: link) == nil)
        #expect(ReaderTarget(link: link, fallbackTopic: readerTopic) == nil)
    }

    /// A private message link keeps its page; with a message number HFR picks the page (the router's rule for every
    /// `forum2.php` link).
    @Test func aPrivateMessageLinkOpensItsThread() throws {
        let thread = TopicID(category: .privateMessages, topic: 4242)
        let page = try #require(ReaderTarget(link: "/forum2.php?config=hfr.inc&cat=prive&post=4242&page=3&p=1#bas"))
        #expect(page == ReaderTarget(source: .topic(thread), page: 3))
        let message = try #require(ReaderTarget(link: "/forum2.php?config=hfr.inc&cat=prive&post=4242&page=3&numreponse=77#t77"))
        #expect(message == ReaderTarget(source: .topic(thread), anchor: 77, numreponse: 77))
    }

    @Test(arguments: [
        "https://example.com/forum2.php?cat=13&post=1&page=2", "https://forum.hardware.fr:8443/forum2.php?cat=13&post=1&page=2",
        "http://forum.hardware.fr:80/forum2.php?cat=13&post=1", "https://user@forum.hardware.fr/forum2.php?cat=13&post=1",
        "/hfr/Discussions/liste_sujet-1.htm", "javascript:alert(1)", "https://forum.hardware.fr/user/logout.php"
    ])
    func otherLinksAreNotTopicPages(_ link: String) {
        #expect(ReaderTarget(link: link) == nil)
    }

    @Test func aCanonicalLinkDropsItsQuery() throws {
        let link = "https://forum.hardware.fr/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_3.htm?logout=1&x=2#t301"
        let target = try #require(ReaderTarget(link: link))
        #expect(target == ReaderTarget(source: .topic(readerTopic), page: 3, anchor: 301))
    }

    @Test func anHTTPForumLinkIsFetchedOverHTTPS() throws {
        let url = try #require(ReaderTarget.forumURL("http://forum.hardware.fr/hfr/a/b-sujet_1_2.htm"))
        #expect(url.absoluteString == "https://forum.hardware.fr/hfr/a/b-sujet_1_2.htm")
    }

    @Test func aFlaggedRowOpensAtItsFlag() throws {
        var row = TopicSummary(topicID: readerTopic, title: "Pizza", path: "/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_1.htm")
        row.flagPath = flagLink.replacing("page=1&", with: "page=7&")
        let target = try #require(ReaderTarget(opening: row))
        #expect(target == ReaderTarget(source: .topic(readerTopic), page: 7, anchor: 2666649))
    }

    @Test func anUnflaggedRowOpensItsOwnLink() throws {
        let row = TopicSummary(topicID: readerTopic, title: "Pizza", path: "/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_1.htm")
        let target = try #require(ReaderTarget(opening: row))
        #expect(target == ReaderTarget(source: .topic(readerTopic), page: 1))
    }

    @Test func aRowWithAnUnreadableLinkFallsBackToItsTopic() throws {
        let row = TopicSummary(topicID: readerTopic, title: "Pizza", path: "/weird", currentPage: 3)
        #expect(try #require(ReaderTarget(opening: row)) == ReaderTarget(source: .topic(readerTopic), page: 3))
        #expect(ReaderTarget(opening: TopicSummary(title: "Nothing", path: "/weird")) == nil)
    }

    @Test func movingToAnotherPageDropsTheAnchor() {
        let target = ReaderTarget(source: .topic(readerTopic), page: 2, anchor: 5)
        #expect(target.atPage(4) == ReaderTarget(source: .topic(readerTopic), page: 4))
    }
}
