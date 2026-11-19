import Foundation
import Testing
@testable import HFRParsing

/// Rules of `MessageBlockParser` checked on the LOT-001 captures (facts recorded in HFR-PROTOCOL §6c, LOT-030).
@Suite("Message block parser")
struct MessageBlockParserTests {
    @Test("R20 anonymous page 1: 43 tables, 3 ads skipped, 40 blocks in page order")
    func anonymousFirstPage() throws {
        let blocks = try MessageBlockParser.blocks(in: Fixture.capture("R20-topic-p1-anon"))
        #expect(blocks.count == 40)
        #expect(blocks.allSatisfy { $0.author != MessageBlockParser.advertisementAuthor })
        #expect(!blocks.contains { $0.isContinuation || $0.isDeleted || $0.avatarURL != nil })
        let first = try #require(blocks.first)
        #expect(first.numreponse == 2_666_649)
        #expect(first.author == "user3")
        #expect(first.dateText == "09-05-2004 15:23:09")
        #expect(first.quotedByCount == 11)
        #expect(first.quotedByURL?.absoluteString == "https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=13&subcat=433"
            + "&post=28563&page=1&p=1&sondage=&owntopic=&trash=&trash_post=&print=&numreponse=2666649&quote_only=1&new=0&nojs=0")
        #expect(first.editNote == "user3 le 11-11-2018 à 18:24:51", "the page prints U+00A0 around à; the note is normalized")
        #expect(first.editedBy == "user3")
        #expect(first.contentHTML.contains("<p>"))
        #expect(!first.contentHTML.contains("id=\"para"), "inner HTML only, the wrapper div stays out")
    }

    @Test("Dates resolve to Europe/Paris instants, posting and edit alike")
    func instants() throws {
        let blocks = try MessageBlockParser.blocks(in: Fixture.capture("R20-topic-p1-anon"))
        let first = try #require(blocks.first)
        // 09-05-2004 15:23:09 CEST (UTC+2) and 11-11-2018 18:24:51 CET (UTC+1).
        #expect(first.postedAt == Date(timeIntervalSince1970: 1_084_108_989))
        #expect(first.editedAt == Date(timeIntervalSince1970: 1_541_957_091))
        #expect(blocks.allSatisfy { $0.postedAt != nil })
    }

    @Test("R21 logged in: same posts as R20, no ad block on a logged-in page, zero-width spaces dropped from pseudos")
    func loggedInFirstPage() throws {
        let html = try Fixture.capture("R21-topic-p1-logged-in")
        #expect(html.contains("user3\u{200B}</b>"), "the capture prints the pseudo with U+200B")
        let anonymous = try MessageBlockParser.blocks(in: Fixture.capture("R20-topic-p1-anon"))
        let loggedIn = try MessageBlockParser.blocks(in: html)
        #expect(loggedIn.map(\.numreponse) == anonymous.map(\.numreponse))
        #expect(loggedIn.map(\.author) == anonymous.map(\.author))
        #expect(loggedIn.first?.author == "user3")
    }

    @Test(
        "Pages 2+ open with the continuation block, which repeats the previous page's last post",
        arguments: ["R22a-topic-middle-page-anon", "R22b-topic-last-page-anon", "R24-topic-beyond-last-page-anon",
                    "R26-topic-quotes-smileys-anon", "R27-topic-spoilers-anon", "R28-topic-images-videos-anon"]
    )
    func continuation(capture: String) throws {
        let blocks = try MessageBlockParser.blocks(in: Fixture.capture(capture))
        let first = try #require(blocks.first)
        #expect(first.isContinuation)
        #expect(first.contentHTML.hasPrefix("<p><strong>Reprise du message précédent :</strong>"))
        #expect(blocks.dropFirst().allSatisfy { !$0.isContinuation })
    }

    @Test(
        "Page 1, single pages and MP threads have no continuation block",
        arguments: ["R20-topic-p1-anon", "R23-topic-single-page-anon", "R31-topic-locked-anon", "RA4-mp-thread-both-accounts"]
    )
    func noContinuation(capture: String) throws {
        let blocks = try MessageBlockParser.blocks(in: Fixture.capture(capture))
        #expect(!blocks.isEmpty)
        #expect(blocks.allSatisfy { !$0.isContinuation })
    }

    @Test("R22b last page: 10 blocks with distinct, ascending numbers (the continuation copies a post of the previous page)")
    func lastPage() throws {
        let blocks = try MessageBlockParser.blocks(in: Fixture.capture("R22b-topic-last-page-anon"))
        #expect(blocks.count == 10)
        let numbers = blocks.map(\.numreponse)
        #expect(Set(numbers).count == numbers.count)
        #expect(numbers == numbers.sorted())
    }

    @Test("Edit trailers: cited only, edited only, both, none")
    func trailers() throws {
        let blocks = try MessageBlockParser.blocks(in: Fixture.capture("R32a-topic-poll-anon"))
        let byNumber = Dictionary(uniqueKeysWithValues: blocks.map { ($0.numreponse, $0) })
        let editedOnly = try #require(blocks.first { $0.editNote != nil && $0.quotedByCount == nil })
        #expect(editedOnly.quotedByURL == nil)
        #expect(editedOnly.editedBy != nil && editedOnly.editedAt != nil)
        let both = try #require(blocks.first { $0.editNote != nil && $0.quotedByCount != nil })
        #expect(both.quotedByURL != nil)
        let citedOnly = try #require(blocks.first { $0.editNote == nil && $0.quotedByCount != nil })
        #expect(citedOnly.editedBy == nil && citedOnly.editedAt == nil)
        #expect(blocks.contains { $0.editNote == nil && $0.quotedByCount == nil })
        #expect(byNumber.count == blocks.count)
    }

    @Test("RU2 MP thread: the recipient's own post carries an avatar, the others none; `bas` anchor ignored")
    func privateThreadAvatar() throws {
        let blocks = try MessageBlockParser.blocks(in: Fixture.capture("RU2-mp-thread-recipient-after-owner-delete"))
        #expect(blocks.count == 5)
        #expect(blocks.map(\.author) == ["user2", "user2", "user2", "user2", "user1"])
        #expect(blocks.last?.avatarURL?.absoluteString == "https://forum-images.hardware.fr/images/mesdiscussions-900001.jpg")
        #expect(blocks.dropLast().allSatisfy { $0.avatarURL == nil })
        #expect(blocks.last?.numreponse == 1_980_875_038)
    }

    @Test("RA5 deleted conversation: no block, no error")
    func deletedConversation() throws {
        let blocks = try MessageBlockParser.blocks(in: Fixture.capture("RA5-mp-thread-after-delete-owner"))
        #expect(blocks.isEmpty)
    }

    @Test("A list page has no message block")
    func listPage() throws {
        #expect(try MessageBlockParser.blocks(in: Fixture.capture("R04-list-cat13-p1-anon")).isEmpty)
    }

    @Test("No deleted-message wrapper and no search prefix on the corpus (pending capture)")
    func uncapturedStates() throws {
        for capture in ["R20-topic-p1-anon", "R27-topic-spoilers-anon", "RA3-mp-thread-before-cleanup"] {
            let html = try Fixture.capture(capture)
            #expect(!html.contains("messagetabledel"))
            #expect(try MessageBlockParser.blocks(in: html).allSatisfy { !$0.isDeleted })
        }
    }

    @Test("Content HTML is served as written: code block lines stay adjacent, blank lines stay empty")
    func codeBlocksKeepTheirLines() throws {
        let blocks = try MessageBlockParser.blocks(in: Fixture.capture("R27b-topic-code-blocks-anon"))
        let code = try #require(blocks.first { $0.contentHTML.contains("class=\"olcode\"") })
        // The page serves `</li><li></li><li>` for a blank line; pretty-printing would put each item on its own line.
        #expect(code.contentHTML.contains("</li><li></li><li>"))
        #expect(code.contentHTML.contains("<span style=\"color:blue\">#include</span>"))
    }

    @Test("Block without author cell is a typed error")
    func missingAuthor() {
        let html = "<table class=\"messagetable\"><tr><td><a name=\"t1\"></a></td><td><div id=\"para1\">x</div></td></tr></table>"
        #expect(throws: ParsingError.missingElement("class=s2")) { try MessageBlockParser.blocks(in: html) }
    }

    @Test("Block without post anchor or content is a typed error")
    func missingAnchorOrContent() {
        let noAnchor = "<table class=\"messagetable\"><tr><td><b class=\"s2\">u</b></td><td><div id=\"para1\">x</div></td></tr></table>"
        #expect(throws: ParsingError.missingElement("a[name=t<numreponse>]")) { try MessageBlockParser.blocks(in: noAnchor) }
        let noContent = "<table class=\"messagetable\"><tr><td><a name=\"t1\"></a><b class=\"s2\">u</b></td><td></td></tr></table>"
        #expect(throws: ParsingError.missingElement("id=para<numreponse>")) { try MessageBlockParser.blocks(in: noContent) }
    }

    @Test("Only ParsingError escapes the public API")
    func typedThrows() {
        let typed: (String) throws(ParsingError) -> [MessageBlock] = MessageBlockParser.blocks(in:)
        #expect(throws: Never.self) { try typed("<html><body></body></html>") }
    }
}

/// #1186: one unreadable block no longer makes the page unreadable; the R20 capture is broken in memory, one field at a time.
@Suite("Message block parser: unreadable blocks")
struct MessageBlockUnreadableTests {
    /// R20's second message.
    static let target = 2_666_682

    /// `html` with `old` replaced by `new` inside the message table of `numreponse` only.
    static func breaking(_ html: String, block numreponse: Int, _ old: String, _ new: String) throws -> String {
        let anchor = try #require(html.range(of: "name=\"t\(numreponse)\""))
        let start = try #require(html.range(of: "class=\"messagetable\"", options: .backwards, range: html.startIndex..<anchor.lowerBound))
        let end = html.range(of: "class=\"messagetable\"", range: anchor.upperBound..<html.endIndex)?.lowerBound ?? html.endIndex
        let table = html[start.lowerBound..<end]
        #expect(table.contains(old), "the mutation must hit the block")
        return html.replacingCharacters(in: start.lowerBound..<end, with: table.replacing(old, with: new))
    }

    @Test(
        "A block without its anchor, its author cell or its content is skipped; the others stay, in order",
        arguments: [
            ("name=\"t\(target)\"", "name=\"x\(target)\""),
            ("class=\"s2\"", "class=\"s3\""),
            ("id=\"para\(target)\"", "id=\"body\(target)\"")
        ]
    )
    func skipsUnreadableBlock(old: String, new: String) throws {
        let html = try Fixture.capture("R20-topic-p1-anon")
        let expected = try MessageBlockParser.blocks(in: html).map(\.numreponse).filter { $0 != Self.target }
        let broken = try Self.breaking(html, block: Self.target, old, new)
        #expect(try MessageBlockParser.blocks(in: broken).map(\.numreponse) == expected)
        let document = try HTMLDocumentLoader.document(from: broken)
        let extraction = try MessageBlockParser.extraction(from: document)
        #expect(extraction.skipped == 1)
        #expect(extraction.leadingFailure == nil)
        // The action links stay aligned with the blocks (`TopicPageSource` pairs them by position).
        #expect(try MessageActionsParser.actions(in: broken).count == expected.count)
    }

    /// Only the page's first message block can be the continuation copy: with that block skipped, a later message that starts
    /// with the same lead (R22a's own markup, moved in memory) is an ordinary message, keeping its menu and its filtering.
    @Test("A block after a skipped first block is never the continuation copy")
    func aBlockAfterASkippedFirstOneIsNotTheContinuation() throws {
        let html = try Fixture.capture("R22a-topic-middle-page-anon")
        #expect(try MessageBlockParser.blocks(in: html).first?.isContinuation == true)
        let lead = "<p><strong>Reprise du message précédent :</strong><br />"
        var broken = try Self.breaking(html, block: 39_966_395, "name=\"t39966395\"", "name=\"x39966395\"")
        broken = try Self.breaking(broken, block: 39_966_452, "id=\"para39966452\"><p>", "id=\"para39966452\">\(lead)")
        let blocks = try MessageBlockParser.blocks(in: broken)
        let second = try #require(blocks.first)
        #expect(second.numreponse == 39_966_452)
        #expect(second.contentHTML.hasPrefix(lead), "the mutation must reach the content")
        #expect(!second.isContinuation)
    }

    @Test("A page whose every block is unreadable is still an error, not an empty topic")
    func everyBlockBrokenThrows() throws {
        let html = try Fixture.capture("R20-topic-p1-anon").replacing("name=\"t", with: "name=\"x")
        #expect(throws: ParsingError.missingElement("a[name=t<numreponse>]")) { try MessageBlockParser.blocks(in: html) }
    }

    @Test("MPStorage refuses a page whose first block is unreadable: the next message must not pass for the document")
    func storageRefusesAnUnreadableFirstBlock() throws {
        let html = try Fixture.capture("R20-topic-p1-anon")
        let broken = try Self.breaking(html, block: 2_666_649, "name=\"t2666649\"", "name=\"x2666649\"")
        #expect(throws: MPStoragePageError.unreadablePage(.missingElement("a[name=t<numreponse>]"))) {
            try MPStoragePageParser.locateMessage(in: broken)
        }
    }
}
