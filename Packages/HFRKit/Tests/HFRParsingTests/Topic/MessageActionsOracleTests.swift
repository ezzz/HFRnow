import Foundation
import HFRModels
import Testing
@testable import HFRParsing

/// Differential tests (ADR 0004): the action links of every message of every LOT-003 topic oracle against
/// `MessageActionsParser` on its capture (`docs/lots/LOT-031-message-actions.md`, "Oracle coverage").
@Suite("Message actions vs LOT-003 oracle")
struct MessageActionsOracleTests {
    @Test("Action URLs and multi-quote arguments equal the legacy actions dictionary", arguments: MessageBlockOracleTests.cases)
    func matchesOracle(caseID: String) throws {
        let map = try TopicOracle.loadMap()
        let entry = try #require(map[caseID])
        let oracle = try MessageActionsOracle.load(caseID)
        #expect(oracle.exception == nil)
        let actions = try MessageActionsParser.actions(in: TopicOracle.capture(for: entry))
        try #require(actions.count == oracle.result.messages.count, "\(caseID): one action set per message")
        try #require(oracle.result.actions.map(\.index) == Array(oracle.result.messages.indices), "\(caseID): one entry per message")

        for (parsed, expected) in zip(actions, oracle.result.actions) {
            let label = "\(caseID) message \(expected.index)"
            #expect(parsed.quoteURL?.absoluteString == expected.quoteURL, "\(label): quoteURL")
            #expect(parsed.editURL?.absoluteString == expected.editURL, "\(label): editURL")
            #expect(parsed.alertURL?.absoluteString == expected.alertURL, "\(label): alertURL")
            #expect(parsed.profileURL?.absoluteString == expected.profileURL, "\(label): profileURL")
            #expect(parsed.privateMessageURL?.absoluteString == expected.privateMessageURL, "\(label): privateMessageURL")
            #expect(parsed.favoriteURL?.absoluteString == expected.favoriteURL, "\(label): favoriteURL")
            #expect(parsed.quoteSelection.map(Self.cookieSelection) == expected.quoteJS.flatMap(Self.legacyCookieSelection),
                    "\(label): quoteJS")
        }
    }

    @Test("The comparison is not vacuous: the corpus offers every action at least once")
    func corpusCoversEveryAction() throws {
        var seen = Set<String>()
        for caseID in MessageBlockOracleTests.cases {
            for entry in try MessageActionsOracle.load(caseID).result.actions {
                let offered: [(String, String?)] = [
                    ("quote", entry.quoteURL), ("edit", entry.editURL), ("alert", entry.alertURL), ("profile", entry.profileURL),
                    ("mp", entry.privateMessageURL), ("favorite", entry.favoriteURL), ("quoteJS", entry.quoteJS)
                ]
                seen.formUnion(offered.compactMap { $0.1 == nil ? nil : $0.0 })
            }
        }
        #expect(seen == ["quote", "edit", "alert", "profile", "mp", "favorite", "quoteJS"])
    }

    // MARK: - Multi-quote, compared the way the legacy app used it

    /// Cookie name and message id the token selects (HFR-PROTOCOL §4: `quotes<arg0>-<arg1>-<arg2>`, value `|<arg3>`).
    static func cookieSelection(_ token: QuoteSelectionToken) -> String {
        "quotes\(token.forum)-\(token.topic.category.queryValue)-\(token.topic.topic)|\(token.numreponse)"
    }

    /// The same pair read from the legacy `quoteJS` string as the legacy app did (`MessagesView.swift:1852-1876`):
    /// arguments between the parentheses, split on commas, quotes stripped.
    static func legacyCookieSelection(_ quoteJS: String) -> String? {
        guard
            let open = quoteJS.firstIndex(of: "("),
            let close = quoteJS[open...].firstIndex(of: ")")
        else { return nil }
        let values = quoteJS[quoteJS.index(after: open)..<close]
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces).replacing("'", with: "").replacing("\"", with: "") }
            .filter { !$0.isEmpty }
        guard values.count >= 4 else { return nil }
        return "quotes\(values[0])-\(values[1])-\(values[2])|\(values[3])"
    }
}
