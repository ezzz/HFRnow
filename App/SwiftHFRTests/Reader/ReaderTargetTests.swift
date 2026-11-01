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
        let link = "http://forum.hardware.fr/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_1353.htm#t44795902"
        let target = try #require(ReaderTarget(link: link))
        #expect(target.source == .path("/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_1353.htm"))
        #expect(target.page == 1353)
        #expect(target.anchor == 44795902)
        let known = try #require(ReaderTarget(link: link, fallbackTopic: readerTopic))
        #expect(known.source == .topic(readerTopic))
        #expect(known.page == 1353)
        #expect(known.anchor == 44795902)
        // The same number in another category is another topic: the category is not borrowed.
        let other = try #require(ReaderTarget(link: link, fallbackTopic: TopicID(category: .forum(5), topic: 1)))
        #expect(other.source == .path("/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_1353.htm"))
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
        #expect(target.source == .path("/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_3.htm"))
        #expect(target.page == 3)
        #expect(target.anchor == 301)
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
        let path = ReaderTarget(source: .path("/hfr/a/b-sujet_1_2.htm"), page: 2, anchor: 5)
        #expect(path.atPage(9) == ReaderTarget(source: .path("/hfr/a/b-sujet_1_9.htm"), page: 9))
    }
}
