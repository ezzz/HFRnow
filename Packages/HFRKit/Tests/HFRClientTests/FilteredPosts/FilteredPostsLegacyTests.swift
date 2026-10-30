import Foundation
import HFRModels
import HFRParsing
import Testing
@testable import HFRClient

/// Differential tests (ADR 0004, LESSONS 52): the LOT-003 oracles hold what legacy read on each message (`name`,
/// `quotedNB`, `dicoHTML`, run outside filter mode); legacy's filter rule (`ParseMessagesOperation.m:141-347`) is applied
/// to those fields here and must keep the same messages as `FilteredPostsCriteria` on our reading of the same capture.
@Suite("Post filter vs legacy (LOT-003 oracles)")
struct FilteredPostsLegacyTests {
    /// The anonymous topic pages: the filter reads pages without cookies, as these were captured.
    static let cases = ["R20", "R22a", "R22b", "R23", "R26", "R27", "R27b", "R28", "R31", "R32a"]

    /// What legacy read on one message.
    struct LegacyMessage {
        let number: Int
        let name: String
        let quotedNB: String?
        let html: String
    }

    static func oracle(_ id: String) throws -> (messages: [LegacyMessage], capture: String) {
        let directory = Capture.directory.deletingLastPathComponent()
        let url = directory.appendingPathComponent("LOT-003/\(id).oracle.json")
        let root = try JSONSerialization.jsonObject(with: try Data(contentsOf: url)) as? [String: Any]
        let input = root?["input"] as? [String: Any]
        let messages = (root?["result"] as? [String: Any])?["messages"] as? [[String: Any]]
        guard let file = input?["file"] as? String, let messages else { throw Capture.Missing(name: id + ".oracle") }
        let page = try String(contentsOf: directory.appendingPathComponent("LOT-003/" + file), encoding: .utf8)
        let legacy = try messages.map { message in
            guard let postID = message["postID"] as? String, let number = Int(postID.dropFirst()),
                  let name = message["name"] as? String, let html = message["dicoHTML"] as? String
            else { throw Capture.Missing(name: id + ".oracle message") }
            return LegacyMessage(number: number, name: name, quotedNB: message["quotedNB"] as? String, html: html)
        }
        return (legacy, page)
    }

    /// Legacy's rule on one message, past the first block of the page (`:141-144`).
    static func legacyKeeps(_ message: LegacyMessage, own: String?, whitelist: [String], minimum: Int) -> Bool {
        let name = message.name.lowercased()
        let own = own?.lowercased()
        if name == own || whitelist.map({ $0.lowercased() }).contains(name) { return true }   // :181-186
        // :196-206: each `citation` header "<author> a écrit :" minus its last 10 characters, nested quotes included.
        let headers = message.html.matches(of: /<a[^>]*class="Topic"[^>]*>(.*?)<\/a>/).map { String($0.output.1) }
        if let own, headers.contains(where: { $0.count > 10 && $0.dropLast(10).lowercased() == own }) { return true }
        if let own, message.html.lowercased().contains(own) { return true }                      // :327-331
        let count = Int((message.quotedNB ?? "").trimmingCharacters(in: .whitespaces)) ?? 0     // :336-347
        return message.quotedNB != nil && count >= (minimum > 0 ? minimum : 3)
    }

    /// Criteria built from the page's own authors: the most frequent one as the account, the next as whitelisted.
    static func criteriaSets(_ messages: [LegacyMessage]) -> [FilteredPostsCriteria] {
        var counts: [String: Int] = [:]
        for message in messages where !message.name.contains("\u{200B}") { counts[message.name, default: 0] += 1 }
        let authors = counts.sorted { ($0.value, $1.key) > ($1.value, $0.key) }.map(\.key)
        let own = authors.first
        let listed = Array(authors.dropFirst().prefix(1))
        return [
            FilteredPostsCriteria(minimumQuoteCount: 1),
            FilteredPostsCriteria(minimumQuoteCount: 2, pseudo: own, whitelist: listed),
            FilteredPostsCriteria(minimumQuoteCount: 0, pseudo: own, whitelist: listed, includesWhitelist: false),
            FilteredPostsCriteria(pseudo: listed.first, whitelist: own.map { [$0] } ?? [])
        ]
    }

    @Test("Every message but the first of the page is kept exactly when legacy keeps it", arguments: cases)
    func sameSelection(id: String) throws {
        let oracle = try Self.oracle(id)
        let blocks = try MessageBlockParser.blocks(in: oracle.capture)
        try #require(blocks.map(\.numreponse) == oracle.messages.map(\.number), "\(id): same messages in order")
        var compared = 0
        for criteria in Self.criteriaSets(oracle.messages) {
            let whitelist = criteria.includesWhitelist ? criteria.whitelist : []
            for (block, legacy) in zip(blocks, oracle.messages).dropFirst() {
                let quotes = try MessageQuoteAnalyzer.quotes(inContentHTML: block.contentHTML)
                let expected = Self.legacyKeeps(
                    legacy, own: criteria.pseudo, whitelist: whitelist, minimum: criteria.minimumQuoteCount
                )
                #expect(criteria.keeps(block, quotes: quotes) == expected, "\(id) message \(block.numreponse), \(criteria)")
                compared += 1
            }
        }
        #expect(compared == (oracle.messages.count - 1) * 4)
    }

    /// How many times each rule kept a message over the comparison, and how many messages no rule kept.
    struct RuleCounts {
        var byCount = 0, byAuthor = 0, byWhitelist = 0, byQuote = 0, byMention = 0, dropped = 0
    }

    @Test("The comparison is not vacuous: each rule keeps messages somewhere in the corpus, and some are left out")
    func everyRuleFires() throws {
        var kept = RuleCounts()
        for id in Self.cases {
            let oracle = try Self.oracle(id)
            for criteria in Self.criteriaSets(oracle.messages) {
                for message in oracle.messages.dropFirst() {
                    let own = criteria.pseudo?.lowercased()
                    let headers = message.html.matches(of: /<a[^>]*class="Topic"[^>]*>(.*?)<\/a>/).map { String($0.output.1) }
                    if Int(message.quotedNB ?? "") ?? 0 >= criteria.effectiveMinimumQuoteCount { kept.byCount += 1 }
                    if message.name.lowercased() == own { kept.byAuthor += 1 }
                    if criteria.includesWhitelist, criteria.whitelist.contains(message.name) { kept.byWhitelist += 1 }
                    if let own, headers.contains(where: { $0.dropLast(10).lowercased() == own }) { kept.byQuote += 1 }
                    if let own, message.name.lowercased() != own, message.html.lowercased().contains(own) { kept.byMention += 1 }
                    let legacy = Self.legacyKeeps(
                        message, own: criteria.pseudo, whitelist: criteria.includesWhitelist ? criteria.whitelist : [],
                        minimum: criteria.minimumQuoteCount
                    )
                    if !legacy { kept.dropped += 1 }
                }
            }
        }
        #expect(kept.byCount > 0 && kept.byAuthor > 0 && kept.byWhitelist > 0)
        #expect(kept.byQuote > 0 && kept.byMention > 0 && kept.dropped > 0)
    }
}
