import Foundation
import HFRModels
import Testing
@testable import HFRParsing

/// Rules of `MessageActionsParser` on the LOT-001 captures and on inline blocks for the states and attacks no capture
/// shows (facts recorded in HFR-PROTOCOL §6c, LOT-031).
@Suite("Message actions parser")
struct MessageActionsParserTests {
    // MARK: - Captures

    @Test("R21 logged in: every link of a member's message, de-obfuscated and absolute")
    func loggedInMessage() throws {
        let actions = try MessageActionsParser.actions(in: Fixture.capture("R21-topic-p1-logged-in"))
        #expect(actions.count == 40)
        let second = try #require(actions.dropFirst().first)
        let forum = "https://forum.hardware.fr"
        #expect(second.quoteURL?.absoluteString == forum + "/message.php?config=hfr.inc&cat=13&post=28563&numrep=2666682&ref=2"
            + "&page=1&p=1&subcat=433&sondage=0&owntopic=0&new=0#formulaire")
        #expect(second.editURL == nil, "not the visitor's message")
        #expect(second.alertURL?.absoluteString
            == forum + "/user/modo.php?config=hfr.inc&cat=13&post=28563&numreponse=2666682&page=1&ref=2")
        #expect(second.profileURL?.absoluteString == forum + "/hfr/profil-910002.htm")
        #expect(second.privateMessageURL?.absoluteString == forum + "/message.php?config=hfr.inc&cat=prive&sond=&p=1&subcat=&dest=user4"
            + "&subcatgroup=0")
        #expect(second.favoriteURL?.absoluteString == forum + "/user/addflag.php?config=hfr.inc&cat=13&post=28563&numreponse=2666682"
            + "&page=1&ref=2&p=1&sondage=0&owntopic=0&subcat=433")
        #expect(second.quoteSelection == QuoteSelectionToken(forum: "hardwarefr", topic: TopicID(category: .forum(13), topic: 28563),
                                                              numreponse: 2_666_682))
    }

    @Test("R20 logged out: quote and profile only on every message")
    func anonymousPage() throws {
        let actions = try MessageActionsParser.actions(in: Fixture.capture("R20-topic-p1-anon"))
        #expect(actions.count == 40)
        #expect(actions.allSatisfy { $0.quoteURL != nil && $0.profileURL != nil })
        #expect(actions.allSatisfy {
            $0.editURL == nil && $0.alertURL == nil && $0.privateMessageURL == nil && $0.favoriteURL == nil && $0.quoteSelection == nil
        })
    }

    @Test("RA4 owner view of a conversation: edit on own posts, MP on the other account's, private multi-quote")
    func privateThread() throws {
        let actions = try MessageActionsParser.actions(in: Fixture.capture("RA4-mp-thread-both-accounts"))
        #expect(actions.map { $0.editURL != nil } == [true, true, true, true, false])
        #expect(actions.map { $0.privateMessageURL != nil } == [false, false, false, false, true])
        #expect(actions.allSatisfy { $0.alertURL == nil && $0.favoriteURL == nil })
        let first = try #require(actions.first)
        #expect(first.editURL?.absoluteString == "https://forum.hardware.fr/message.php?config=hfr.inc&cat=prive&post=3207033"
            + "&numreponse=1980875029&page=1&p=1&subcat=0&sondage=0&owntopic=0#formulaire")
        #expect(first.quoteSelection?.topic == TopicID(category: .privateMessages, topic: 3_207_033))
    }

    @Test("R22a: a message without profile link (author account gone) has the quote link only")
    func messageWithoutProfile() throws {
        let html = try Fixture.capture("R22a-topic-middle-page-anon")
        let blocks = try MessageBlockParser.blocks(in: html)
        let actions = try MessageActionsParser.actions(in: html)
        let index = try #require(blocks.firstIndex { $0.numreponse == 39_973_901 })
        #expect(actions[index] == MessageActions(quoteURL: actions[index].quoteURL))
        #expect(actions[index].quoteURL != nil)
        #expect(actions.filter { $0.profileURL == nil }.count == 3)
    }

    @Test("Page-level links stay out: the header delflag and the topic alert link are not message actions")
    func pageLevelLinks() throws {
        let html = try Fixture.capture("R21-topic-p1-logged-in")
        #expect(html.contains("/user/delflag.php?"), "the capture has the topic's delflag link")
        #expect(html.contains("/user/modo.php?cat=13&amp;ref=0&amp;post=28563"), "and a topic-level alert link")
        let actions = try MessageActionsParser.actions(in: html)
        #expect(!actions.contains { $0.favoriteURL?.absoluteString.contains("delflag") == true })
        #expect(!actions.contains { $0.alertURL?.absoluteString.contains("ref=0") == true })
    }

    @Test("A page without message gives no action set", arguments: ["RA5-mp-thread-after-delete-owner", "R04-list-cat13-p1-anon"])
    func noMessages(capture: String) throws {
        #expect(try MessageActionsParser.actions(in: Fixture.capture(capture)).isEmpty)
    }

    // MARK: - Inline blocks (states no capture shows)

    @Test("Links posted in the message body are never actions")
    func bodyLinksIgnored() throws {
        let body = """
            <a href="/user/addflag.php?config=hfr.inc&amp;cat=13&amp;post=1&amp;numreponse=9">x</a>
            <a href="/user/modo.php?config=hfr.inc&amp;cat=13&amp;post=1&amp;numreponse=9">y</a>
            <a href="/message.php?config=hfr.inc&amp;cat=prive&amp;dest=someone">z</a>
            <a href="/hfr/profil-1.htm"><img alt="profil" src="p.gif"></a>
            <span class="\(ObfuscatedURL.encode("/message.php?numrep=9", prefix: .noClass))"><img alt="edit" src="e.gif"></span>
            <a onclick="quoter('hardwarefr','13',1,9); return false;" href="#">q</a>
            """
        let actions = try Self.actions(toolbar: "<div class=\"left\">Posté le 01-01-2020&nbsp;à&nbsp;10:00:00</div>", body: body)
        #expect(actions == MessageActions())
    }

    @Test("Derived from R21 (toolbar of message 1 moved into its content): a toolbar inside the content gives no action")
    func toolbarInsideContentIgnored() throws {
        // Derived page, not a capture: one change to R21, the second block's `div.toolbar` moved into its `div#para`, the shape a
        // member's own markup would have when HFR prints no toolbar.
        let original = try Fixture.capture("R21-topic-p1-logged-in")
        let anchor = try #require(original.range(of: "<a name=\"t2666682\">"))
        let start = try #require(original.range(of: "<div class=\"toolbar\">", range: anchor.upperBound..<original.endIndex))
        let paraTag = "<div id=\"para2666682\">"
        let para = try #require(original.range(of: paraTag, range: start.upperBound..<original.endIndex))
        let toolbar = original[start.lowerBound..<para.lowerBound]
        var derived = original
        derived.replaceSubrange(start.lowerBound..<para.upperBound, with: paraTag + toolbar)
        let before = try MessageActionsParser.actions(in: original)
        #expect(before[1].favoriteURL != nil && before[1].quoteSelection != nil, "the toolbar of the capture is read")
        let after = try MessageActionsParser.actions(in: derived)
        try #require(after.count == 40)
        #expect(after[1] == MessageActions())
        #expect(after[0] == before[0] && Array(after[2...]) == Array(before[2...]), "other blocks are unchanged")
    }

    @Test("A block without toolbar has no action, even with action-like links in its content")
    func missingToolbarGivesNoAction() throws {
        let html = Self.page(cells: "<td><div id=\"para9\"><a href=\"/user/addflag.php?post=1\">x</a></div></td>")
        #expect(try MessageActionsParser.actions(in: html) == [MessageActions()])
    }

    @Test("Links that leave the forum origin are dropped", arguments: [
        "https://evil.example/user/modo.php?x=1",
        "//evil.example/user/modo.php?x=1",
        "http://forum.hardware.fr:80/user/modo.php?x=1",
        "https://forum.hardware.fr@evil.example/user/modo.php",
        "javascript:alert('/user/modo.php')",
        "/\\evil.example/user/modo.php"
    ])
    func offOriginAlert(href: String) throws {
        let escaped = href.replacing("&", with: "&amp;").replacing("\"", with: "&quot;")
        let actions = try Self.actions(toolbar: "<a href=\"\(escaped)\">!</a>")
        #expect(actions.alertURL == nil)
    }

    @Test("An http forum link without port is upgraded; a relative one is resolved on the forum root")
    func forumOriginForms() throws {
        let toolbar = """
            <a href="http://forum.hardware.fr/user/modo.php?a=1&amp;b=2">!</a>
            <a href="user/addflag.php?post=1"><img alt="Favoris" src="f.gif"></a>
            <a href="https://forum.hardware.fr/hfr/profil-5.htm"><img alt="profil" src="p.gif"></a>
            """
        let actions = try Self.actions(toolbar: toolbar)
        #expect(actions.alertURL?.absoluteString == "https://forum.hardware.fr/user/modo.php?a=1&b=2")
        #expect(actions.favoriteURL?.absoluteString == "https://forum.hardware.fr/user/addflag.php?post=1")
        #expect(actions.profileURL?.absoluteString == "https://forum.hardware.fr/hfr/profil-5.htm")
    }

    @Test("Obfuscated quote and edit links: decoded, in clear, off origin or undecodable")
    func obfuscatedLinks() throws {
        func toolbar(quoteClass: String) -> String {
            "<span class=\"\(quoteClass)\"><img alt=\"answer\" src=\"q.gif\"></span>"
        }
        let decoded = try Self.actions(toolbar: toolbar(quoteClass: ObfuscatedURL.encode("/message.php?numrep=9", prefix: .noClass)))
        #expect(decoded.quoteURL?.absoluteString == "https://forum.hardware.fr/message.php?numrep=9")
        let clear = try Self.actions(toolbar: toolbar(quoteClass: "/message.php?numrep=9"))
        #expect(clear.quoteURL?.absoluteString == "https://forum.hardware.fr/message.php?numrep=9", "legacy used a clear link as is")
        let elsewhere = try Self.actions(toolbar: toolbar(quoteClass: ObfuscatedURL.encode("https://evil.example/m", prefix: .noClass)))
        #expect(elsewhere.quoteURL == nil)
        #expect(try Self.actions(toolbar: toolbar(quoteClass: "md_noclass_cryptlinkZZ")).quoteURL == nil, "undecodable payload")
        #expect(try Self.actions(toolbar: toolbar(quoteClass: "quote")).quoteURL == nil, "a class name is not a link")
        let plus = "<a class=\"/message.php?numrep=9\"><img alt=\"answer +\" src=\"q.gif\"></a>"
        #expect(try Self.actions(toolbar: plus).quoteURL == nil, "the alt is matched whole: `answer +` is the multi-quote image")
    }

    @Test("New-MP link: read by its parameters, not by the literal legacy prefix")
    func privateMessageLink() throws {
        let reordered = "<a href=\"/message.php?cat=prive&amp;dest=user9&amp;config=hfr.inc\"><img alt=\"MP\" src=\"m.gif\"></a>"
        #expect(try Self.actions(toolbar: reordered).privateMessageURL?.absoluteString
            == "https://forum.hardware.fr/message.php?cat=prive&dest=user9&config=hfr.inc")
        let absolute = "<a href=\"https://forum.hardware.fr/message.php?config=hfr.inc&amp;cat=prive&amp;dest=user9\">MP</a>"
        #expect(try Self.actions(toolbar: absolute).privateMessageURL?.absoluteString
            == "https://forum.hardware.fr/message.php?config=hfr.inc&cat=prive&dest=user9")
        let quotePlus = "<a href=\"/message.php?config=hfr.inc&amp;cat=prive&amp;post=3&amp;numrep=9&amp;ref=1#formulaire\">+</a>"
        #expect(try Self.actions(toolbar: quotePlus).privateMessageURL == nil, "no dest: the multi-quote link of an MP thread")
        let emptyDest = "<a href=\"/message.php?config=hfr.inc&amp;cat=prive&amp;dest=\">+</a>"
        #expect(try Self.actions(toolbar: emptyDest).privateMessageURL == nil)
        let publicCategory = "<a href=\"/message.php?config=hfr.inc&amp;cat=13&amp;dest=user9\">+</a>"
        #expect(try Self.actions(toolbar: publicCategory).privateMessageURL == nil)
    }

    @Test("Multi-quote arguments: quoted or not, private category, and only for this block's message")
    func quoteSelection() throws {
        func token(_ onclick: String) throws -> QuoteSelectionToken? {
            try Self.actions(toolbar: "<a onclick=\"\(onclick)\" href=\"#\">+</a>").quoteSelection
        }
        let expected = QuoteSelectionToken(forum: "hardwarefr", topic: TopicID(category: .forum(13), topic: 42), numreponse: 9)
        #expect(try token("quoter('hardwarefr','13',42,9); return false;") == expected)
        #expect(try token("quoter('hardwarefr' , 13 , '42' , '9' )") == expected)
        #expect(try token("quoter('hardwarefr','prive',42,9)")?.topic.category == .privateMessages)
        #expect(try token("quoter('hardwarefr','13',42,8)") == nil, "another message's number")
        #expect(try token("quoter('otherforum','13',42,9)") == nil)
        #expect(try token("quoter('otherforum','13',42,9); quoter('hardwarefr','13',42,9)") == nil,
                "the call read must be the hardwarefr one the element was selected for")
        #expect(try token("quoter('hardwarefr','13',42,9,'extra')") == expected, "legacy read the first four of four or more")
        #expect(try token("quoter('hardwarefr','13',42,9x)") == nil)
        #expect(try token("quoter('hardwarefr','x-1',42,9)") == nil, "not a category")
        #expect(try token("quoter('hardwarefr','13',0,9)") == nil, "topic 0")
    }

    @Test("The public entry point throws ParsingError only")
    func typedThrows() {
        let missingAuthor = "<table class=\"messagetable\"><tr><td><a name=\"t1\"></a></td><td><div id=\"para1\">x</div></td></tr></table>"
        #expect(throws: ParsingError.missingElement("class=s2")) { try MessageActionsParser.actions(in: missingAuthor) }
    }

    // MARK: - Helpers

    /// The single action set of a one-block page whose toolbar holds `toolbar` and whose content holds `body`.
    static func actions(toolbar: String, body: String = "texte") throws -> MessageActions {
        let cells = "<td class=\"messCase2\"><div class=\"toolbar\">\(toolbar)</div><div id=\"para9\">\(body)</div></td>"
        let actions = try MessageActionsParser.actions(in: page(cells: cells))
        try #require(actions.count == 1)
        return actions[0]
    }

    /// A page with one message block numbered 9 by `author`, whose second cell is `cells`.
    static func page(cells: String) -> String {
        "<html><body><table class=\"messagetable\"><tr class=\"message\"><td class=\"messCase1\"><a name=\"t9\"></a>"
            + "<div><b class=\"s2\">author</b></div></td>\(cells)</tr></table></body></html>"
    }
}
