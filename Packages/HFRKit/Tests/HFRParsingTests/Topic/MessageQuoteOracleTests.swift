import Foundation
import HFRModels
import SwiftSoup
import Testing
@testable import HFRParsing

/// Differential tests (ADR 0004) for LOT-032. The LOT-003 oracle exports no per-quote field: its legacy output of record is
/// `dicoHTML`, the content after `ParseMessagesOperation.m:191-226` (quote classes rewritten). The legacy-derivable subset
/// (how many quotes, which authors by the legacy rule) is recomputed from it here; the facts legacy never computed (cited
/// number, depth) are checked against the captures by an independent reader. See `docs/lots/LOT-032-quote-analysis.md`.
@Suite("Quote analysis vs LOT-003 oracle")
struct MessageQuoteOracleTests {
    /// Legacy author rule, `ParseMessagesOperation.m:200-203`: header text minus its last 10 characters, when longer than 10.
    private static func legacyAuthor(of table: Element) throws -> String? {
        guard let header = try table.select("[class=Topic]").first() else { return nil }
        let text = header.rawText
        return text.count > 10 ? String(text.dropLast(10)) : nil
    }

    private struct LegacyQuotes {
        var authors: [String] = []
        var anonymous = 0
    }

    /// What legacy produced for one message, read from the oracle HTML.
    private static func legacyQuotes(inOracleHTML html: String) throws -> LegacyQuotes {
        let body = try #require(try SwiftSoup.parseBodyFragment(html).body())
        var result = LegacyQuotes()
        for table in try body.select("table") {
            let classes = try table.attr("class")
            if classes == "citation", let author = try legacyAuthor(of: table) {
                result.authors.append(author)
            } else if classes == "quote" {
                result.anonymous += 1
            }
        }
        return result
    }

    @Test("Authors and counts equal what legacy derived", arguments: MessageBlockOracleTests.cases)
    func matchesLegacy(caseID: String) throws {
        let map = try TopicOracle.loadMap()
        let entry = try #require(map[caseID])
        let oracle = try TopicOracle.load(caseID)
        let blocks = try MessageBlockParser.blocks(in: TopicOracle.capture(for: entry))
        try #require(blocks.count == oracle.result.messages.count, "\(caseID): block count")
        for (block, expected) in zip(blocks, oracle.result.messages) {
            let label = "\(caseID) message \(expected.index)"
            let legacy = try Self.legacyQuotes(inOracleHTML: try #require(expected.dicoHTML, "\(label): dicoHTML"))
            let quotes = try MessageQuoteAnalyzer.quotes(inContentHTML: block.contentHTML)
            // Exact: the legacy text keeps U+00A0 and U+200B, which the analyzer normalizes like `MessageBlock.author`.
            let legacyAuthors = legacy.authors.map { HFRText.normalizedPseudo($0.replacing("\u{00A0}", with: " ")) }
            #expect(quotes.compactMap(\.author) == legacyAuthors, "\(label): authors")
            #expect(quotes.filter { $0.author == nil }.count == legacy.anonymous, "\(label): anonymous quotes")
        }
    }

    @Test("Cited numbers and depths on the corpus match an independent reading of the capture")
    func newFactsMatchCaptures() throws {
        let map = try TopicOracle.loadMap()
        var total = 0
        for caseID in MessageBlockOracleTests.cases {
            let blocks = try MessageBlockParser.blocks(in: TopicOracle.capture(for: try #require(map[caseID])))
            for block in blocks {
                let quotes = try MessageQuoteAnalyzer.quotes(inContentHTML: block.contentHTML)
                total += quotes.count
                // Independent of the DOM: the header links in text order, `#t<n>` right before `class="Topic"`.
                let fragments = block.contentHTML.matches(of: /#t([0-9]+)" class="Topic">/).compactMap { Int($0.output.1) }
                #expect(quotes.compactMap(\.citedNumreponse) == fragments, "\(caseID) \(block.numreponse): cited numbers")
                #expect(quotes.allSatisfy { $0.author != nil || $0.citedNumreponse == nil }, "\(caseID): anonymous has no link")
                let tableOpens = block.contentHTML.matches(of: /<table class="(?:citation|quote)">/).count
                #expect(quotes.count == tableOpens, "\(caseID) \(block.numreponse): quote count")
            }
        }
        #expect(total == 150, "126 citations + 9 anonymous quotes on the corpus (LOT-034 facts), plus R21's 15 again in P03m")
    }

    @Test("The one nested quote of the corpus: an anonymous quote inside a citation (R28, R32a, R32b message 27)")
    func nestedQuoteOfTheCorpus() throws {
        let map = try TopicOracle.loadMap()
        for (caseID, cited) in [("R28", 75_481_731), ("R32a", 26_360_875), ("R32b", 26_360_875)] {
            let blocks = try MessageBlockParser.blocks(in: TopicOracle.capture(for: try #require(map[caseID])))
            let quotes = try MessageQuoteAnalyzer.quotes(inContentHTML: blocks[27].contentHTML)
            try #require(quotes.count == 2, "\(caseID)")
            #expect(quotes[0].depth == 1 && quotes[0].author != nil && quotes[0].citedNumreponse == cited, "\(caseID)")
            #expect(quotes[1] == MessageQuote(author: nil, depth: 2, citedNumreponse: nil), "\(caseID)")
        }
    }

    @Test("The sanitized HTML of LOT-034 gives the same quotes as the raw content")
    func sameOnSanitizedContent() throws {
        let map = try TopicOracle.loadMap()
        for caseID in MessageBlockOracleTests.cases {
            let blocks = try MessageBlockParser.blocks(in: TopicOracle.capture(for: try #require(map[caseID])))
            for block in blocks {
                let raw = try MessageQuoteAnalyzer.quotes(inContentHTML: block.contentHTML)
                let content = try MessageContentNormalizer.normalize(contentHTML: block.contentHTML)
                #expect(try MessageQuoteAnalyzer.quotes(inContentHTML: content.html) == raw, "\(caseID) \(block.numreponse)")
            }
        }
    }
}
