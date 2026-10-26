import Foundation
import HFRModels
import Testing
@testable import HFRParsing

/// Expectations written from reading the captures (not copied from the oracle), plus defensive cases of the parser itself.
@Suite("Topic page metadata")
struct TopicPageMetadataParserTests {
    private static let pizza = TopicID(category: .forum(13), topic: 28563)

    private func parse(_ capture: String, url: String) throws -> TopicPageMetadata {
        try TopicPageMetadataParser.parse(html: Fixture.capture(capture), pageURL: url)
    }

    // MARK: Captured pages

    @Test("first page, logged in: answer form, 17 hidden fields, search form")
    func loggedInFirstPage() throws {
        let page = try parse("R21-topic-p1-logged-in", url: "/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_1.htm")
        #expect(page.title == "Topic pizza maison")
        #expect(page.currentPage == 1)
        #expect(page.maxPage == 2201)
        #expect(page.topicID == Self.pizza)
        #expect(page.answerFormURL?.absoluteString
            == "https://forum.hardware.fr/message.php?config=hfr.inc&cat=13&post=28563&page=1&p=1&subcat=433&sondage=0&owntopic=0&new=0")
        #expect(page.answerFormFields.count == 17)
        #expect(page.answerFormFields["post"] == "28563")
        #expect(page.answerFormFields["cat"] == "13")
        #expect(page.searchFormFields?.keys.sorted() == ["cat", "firstnum", "hash_check", "p", "post", "spseudo", "word"])
        #expect(!page.isUnreadable)
        #expect(!page.hasPoll)
    }

    @Test("anonymous page: no answer form, no hidden fields, topic identity from the search form")
    func anonymousFirstPage() throws {
        let page = try parse("R20-topic-p1-anon", url: "/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_1.htm")
        #expect(page.answerFormURL == nil)
        #expect(page.answerFormFields.isEmpty)
        #expect(page.topicID == Self.pizza)
        #expect(page.searchFormFields?["hash_check"] == "")
    }

    @Test("middle page and last page: current page from the URL, max page from the pager")
    func middleAndLastPage() throws {
        let middle = try parse("R22a-topic-middle-page-anon", url: "/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_1100.htm")
        #expect((middle.currentPage, middle.maxPage) == (1100, 2201))
        // On the last page the highest number is the current page, printed in <b> instead of a link.
        let last = try parse("R22b-topic-last-page-anon", url: "/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_2201.htm")
        #expect((last.currentPage, last.maxPage) == (2201, 2201))
    }

    @Test("beyond the last page: HFR redirects, the final URL gives the last page")
    func beyondLastPage() throws {
        let page = try parse("R24-topic-beyond-last-page-anon", url: "/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_2201.htm")
        #expect((page.currentPage, page.maxPage) == (2201, 2201))
    }

    @Test("a client that kept the requested URL gets the page it asked for, even beyond maxPage (legacy Q18)")
    func requestedURLIsNotClamped() throws {
        let page = try parse("R24-topic-beyond-last-page-anon", url: "/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_2202.htm")
        #expect((page.currentPage, page.maxPage) == (2202, 2201))
    }

    @Test("single page topic: no pager block, one page")
    func singlePage() throws {
        let page = try parse("R23-topic-single-page-anon", url: "/hfr/Discussions/Loisirs/tequila-jose-cuervo-sujet_91031_1.htm")
        #expect((page.currentPage, page.maxPage) == (1, 1))
        #expect(page.title == "Tequila Jose Cuervo")
    }

    @Test("locked topic as seen by a visitor: no answer form, title kept")
    func lockedTopic() throws {
        let page = try parse("R31-topic-locked-anon", url: "/hfr/Discussions/Actualite/droits-auteurs-articles-sujet_100217_1.htm")
        #expect(page.answerFormURL == nil)
        #expect(page.title == "Rappel sur les droits d'auteurs et le copier coller d'articles")
    }

    @Test("poll block is detected on a poll topic, logged in or not")
    func pollPresence() throws {
        let url = "/hfr/Discussions/Auto-Moto/rouleurs-essence-alcoolisee-sujet_98162_1.htm"
        let anonymous = try parse("R32a-topic-poll-anon", url: url)
        let loggedIn = try parse("R32b-topic-poll-logged-in-not-voted", url: url)
        #expect(anonymous.hasPoll)
        #expect(loggedIn.hasPoll)
    }

    @Test("private conversation: unread link, private category from the form")
    func privateConversation() throws {
        let page = try parse("RU1-mp-thread-recipient-view", url: "/forum2.php?config=hfr.inc&cat=prive&post=3207033&page=1")
        #expect(page.isUnreadable)
        #expect(page.topicID == TopicID(category: .privateMessages, topic: 3207033))
        #expect(page.answerFormFields["cat"] == "prive")
        #expect(page.answerFormURL != nil)
    }

    @Test("conversation after the owner's delete: no reply form, identity still known")
    func deletedByOwnerRecipientView() throws {
        let page = try parse("RU2-mp-thread-recipient-after-owner-delete", url: "/forum2.php?config=hfr.inc&cat=prive&post=3207033&page=1")
        #expect(page.answerFormURL == nil)
        #expect(page.answerFormFields.isEmpty)
        #expect(page.topicID == TopicID(category: .privateMessages, topic: 3207033))
        #expect(page.isUnreadable)
    }

    @Test("conversation deleted by its owner (owner's view): a valid page with nothing in it")
    func deletedConversation() throws {
        let page = try parse("RA5-mp-thread-after-delete-owner", url: "/forum2.php?config=hfr.inc&cat=prive&post=3207033&page=1")
        #expect(page.title.isEmpty)
        #expect(page.maxPage == 1)
        #expect(page.answerFormURL == nil)
        #expect(page.searchFormFields == nil)
        #expect(page.topicID == TopicID(category: .privateMessages, topic: 3207033))
    }

    @Test("descriptions and reflection never print form values (hash_check)")
    func formValuesAreRedacted() throws {
        let page = try parse("R21-topic-p1-logged-in", url: "/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_1.htm")
        let token = try #require(page.answerFormFields["hash_check"])
        #expect(!token.isEmpty)
        var dumped = ""
        dump(page, to: &dumped)
        for text in [page.description, page.debugDescription, "\(page)", dumped] {
            #expect(!text.contains(token))
            #expect(!text.contains("hash_check"))
        }
        #expect(page.description.contains("values redacted"))
    }

    // MARK: Defensive cases (small inline pages; they state parser rules, not HFR facts)

    private func parse(body: String, url: String = "/forum2.php?config=hfr.inc&cat=13&post=1&page=1") throws -> TopicPageMetadata {
        try TopicPageMetadataParser.parse(html: "<html><body>\(body)</body></html>", pageURL: url)
    }

    @Test("an answer link leaving the forum, or not https, is refused")
    func answerLinkMustStayOnTheForum() throws {
        let foreign = try parse(body: #"<div id="repondre_form"><a href="https://evil.example/message.php">x</a></div>"#)
        let insecure = try parse(body: #"<div id="repondre_form"><a href="http://forum.hardware.fr:80/message.php">x</a></div>"#)
        let relative = try parse(body: #"<div id="repondre_form"><a href="/message.php?cat=13&amp;post=1">x</a></div>"#)
        #expect(foreign.answerFormURL == nil)
        #expect(insecure.answerFormURL == nil)
        #expect(relative.answerFormURL?.absoluteString == "https://forum.hardware.fr/message.php?cat=13&post=1")
    }

    @Test("the pager takes the highest number and ignores text around the links")
    func pagerHighestNumber() throws {
        let html = """
        <table><tr class="cBackHeader fondForum2PagesHaut"><td><div class="left">
        <b>Page : </b><a>1</a> .. <a>7</a><b>8</b> suivante</div></td></tr></table>
        """
        #expect(try parse(body: html).maxPage == 8)
        let none = #"<table><tr class="fondForum2PagesHaut"><td><div class="left"><b>Page : </b></div></td></tr></table>"#
        #expect(try parse(body: none).maxPage == 1)
    }

    @Test("quick-answer fields: hidden inputs with name and value only, the last duplicate wins")
    func hiddenFieldRules() throws {
        let html = """
        <form name="hop"><input type="hidden" name="a" value="1"/><input type="hidden" name="a" value="2"/>
        <input type="hidden" name="novalue"/><input type="hidden" value="noname"/><input type="text" name="visible" value="x"/>
        <input type="hidden" name="empty" value=""/></form>
        """
        #expect(try parse(body: html).answerFormFields == ["a": "2", "empty": ""])
    }

    @Test("search form: only the wanted names, a checkbox only when checked")
    func searchFormRules() throws {
        let html = """
        <form action="/transsearch.php"><input type="hidden" name="hash_check" value="t"/>
        <input type="hidden" name="config" value="hfr.inc"/><input type="checkbox" name="filter" value="1"/></form>
        """
        #expect(try parse(body: html).searchFormFields == ["hash_check": "t"])
        let checked = html.replacing(#"name="filter" value="1""#, with: #"name="filter" value="1" checked="checked""#)
        #expect(try parse(body: checked).searchFormFields == ["hash_check": "t", "filter": "1"])
        // HTML input types are case-insensitive: an unchecked CHECKBOX is still dropped.
        let upper = html.replacing(#"type="checkbox""#, with: #"type="CHECKBOX""#)
        #expect(try parse(body: upper).searchFormFields == ["hash_check": "t"])
    }

    @Test("an empty or unrelated document is a page with nothing in it, not an error")
    func emptyDocument() throws {
        let page = try TopicPageMetadataParser.parse(html: "", pageURL: "")
        #expect(page == TopicPageMetadata())
    }

    @Test("topic identity falls back to the page URL when no form has it")
    func topicIDFromURL() throws {
        let page = try parse(body: "", url: "/forum2.php?config=hfr.inc&cat=prive&post=42&page=3")
        #expect(page.topicID == TopicID(category: .privateMessages, topic: 42))
        #expect(page.currentPage == 3)
        #expect(try parse(body: "", url: "/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_4.htm").topicID == nil)
    }
}
