import Foundation
import HFRModels
import HFRParsing
import Testing
@testable import HFRClient

/// The rules legacy's code leaves open, on the messages of `R20` (page 1 of topic 28563, anonymous).
@Suite("Post filter: criteria")
struct FilteredPostsCriteriaTests {
    private static func page() throws -> [(block: MessageBlock, quotes: [MessageQuote])] {
        try MessageBlockParser.blocks(in: try Capture.page("R20-topic-p1-anon")).map { block in
            (block, try MessageQuoteAnalyzer.quotes(inContentHTML: block.contentHTML))
        }
    }

    private static func kept(_ criteria: FilteredPostsCriteria) throws -> [Int] {
        try page().filter { criteria.keeps($0.block, quotes: $0.quotes) }.map(\.block.numreponse)
    }

    @Test("A minimum of 0 or less reads as 3, legacy's floor")
    func minimumFloor() throws {
        let three = try Self.kept(FilteredPostsCriteria(minimumQuoteCount: 3))
        #expect(!three.isEmpty)
        #expect(try Self.kept(FilteredPostsCriteria(minimumQuoteCount: 0)) == three)
        #expect(try Self.kept(FilteredPostsCriteria(minimumQuoteCount: -2)) == three)
        #expect(FilteredPostsCriteria(minimumQuoteCount: -2).effectiveMinimumQuoteCount == 3)
    }

    @Test("Pseudos compare without zero-width spaces and case: R20's first author is printed `user3` + U+200B")
    func pseudoKey() throws {
        let first = try #require(try Self.page().first)
        #expect(first.block.author == "user3")
        let criteria = FilteredPostsCriteria(minimumQuoteCount: 1_000, pseudo: "USER3\u{200B} ")
        #expect(criteria.keeps(first.block, quotes: first.quotes))
        let listed = FilteredPostsCriteria(minimumQuoteCount: 1_000, whitelist: ["User3"])
        #expect(listed.keeps(first.block, quotes: first.quotes))
    }

    @Test("A blank pseudo turns the account's rules off, so it never matches every message", arguments: [nil, "", " \u{200B}"])
    func blankPseudo(pseudo: String?) throws {
        #expect(try Self.kept(FilteredPostsCriteria(minimumQuoteCount: 1_000, pseudo: pseudo)).isEmpty)
    }

    @Test("Whitelisted authors are kept only when the whitelist is on")
    func whitelistSwitch() throws {
        let author = try #require(try Self.page().dropFirst().first?.block.author)
        let on = try Self.kept(FilteredPostsCriteria(minimumQuoteCount: 1_000, whitelist: [author]))
        let off = try Self.kept(FilteredPostsCriteria(minimumQuoteCount: 1_000, whitelist: [author], includesWhitelist: false))
        #expect(!on.isEmpty)
        #expect(off.isEmpty)
    }

    @Test("R20: a personal smiley named after the account (`[:user6]` in message 2666695 by user5) is a mention, as in legacy")
    func mentionBySmiley() throws {
        let message = try #require(try Self.page().first { $0.block.numreponse == 2666695 })
        #expect(message.block.author == "user5")
        #expect(!message.quotes.contains { $0.author == "user6" })
        #expect(FilteredPostsCriteria(minimumQuoteCount: 1_000, pseudo: "user6").keeps(message.block, quotes: message.quotes))
    }

    // MARK: - Rules on small models (no page state: the fields the rules read)

    @Test("A quote of the account counts at any depth, even when the content does not spell the pseudo the same way")
    func quoteAtAnyDepth() {
        // A header holding a zero-width space (HFR puts them in long pseudos, LOT-030) no longer spells the pseudo as text.
        let block = MessageBlock(numreponse: 2, author: "other", contentHTML: "<p>longpseu\u{200B}do a écrit :</p>")
        let criteria = FilteredPostsCriteria(minimumQuoteCount: 1_000, pseudo: "LongPseudo")
        #expect(criteria.keeps(block, quotes: [MessageQuote(author: "longpseudo", depth: 2)]))
        #expect(!criteria.keeps(block, quotes: [MessageQuote(author: nil, depth: 2), MessageQuote(author: "third")]))
    }

    @Test("Authors compare by key: case and zero-width spaces do not matter")
    func authorKey() {
        let block = MessageBlock(numreponse: 2, author: "Membre", contentHTML: "<p>texte</p>")
        #expect(FilteredPostsCriteria(minimumQuoteCount: 1_000, pseudo: "membre").keeps(block, quotes: []))
        #expect(FilteredPostsCriteria(minimumQuoteCount: 1_000, whitelist: ["MEM\u{200B}BRE"]).keeps(block, quotes: []))
    }
}
