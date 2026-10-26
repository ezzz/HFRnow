import Foundation
import HFRModels
import Testing
@testable import HFRParsing

/// Differential tests (ADR 0004) of `PollParser` against the LOT-005 `poll` oracles on the same captures. The whole parsed poll
/// is compared; the three deviations from legacy are normalized explicitly and listed in `docs/lots/LOT-026-poll-parser.md`.
@Suite("Poll parser against the legacy oracle")
struct PollOracleTests {
    static let cases = ["R32a", "R32b", "R33a", "R33b"]

    @Test("the case list covers every LOT-005 poll case")
    func casesCoverTheMap() throws {
        #expect(try Lot005Oracle.mappedCases(ofKinds: ["poll"]) == Set(Self.cases))
    }

    @Test("question, mode, answers, hidden fields and result lines equal the legacy parse", arguments: cases)
    func matchesOracle(id: String) throws {
        let oracle = try Lot005Oracle.load(id)
        let legacyPoll = try #require(oracle.result["poll"] as? [String: Any])
        let legacy = try #require(legacyPoll["parsed"] as? [String: Any])
        #expect(legacyPoll["hasPoll"] as? Bool == true)

        let parsed = try PollParser.poll(in: oracle.html)
        let poll = try #require(parsed)
        #expect(poll.question == legacy["question"] as? String)
        #expect(poll.maxChoices == legacy["maxChoices"] as? Int)

        let isVotable = legacy["isVotable"] as? Bool
        #expect(legacyPoll["isNewVote"] as? Bool == isVotable)
        switch poll.kind {
        case .votable(let options, let hiddenFields):
            #expect(isVotable == true)
            let legacyOptions = try #require(legacy["options"] as? [[String: Any]])
            #expect(options.count == legacyOptions.count)
            for (option, expected) in zip(options, legacyOptions) {
                #expect(option.id == expected["id"] as? Int)
                #expect(option.fieldName == expected["fieldName"] as? String)
                // Deviation 1 (quirk Q7): legacy left `&amp;` in the text.
                #expect(option.text == (expected["text"] as? String)?.replacing("&amp;", with: "&"))
            }
            #expect(hiddenFields == legacy["hiddenFields"] as? [String: String])
            #expect((legacy["results"] as? [Any])?.isEmpty == true)
        case .results(let lines):
            #expect(isVotable == false)
            let legacyLines = try #require(legacy["results"] as? [[String: Any]])
            #expect(lines.count == legacyLines.count)
            for (line, expected) in zip(lines, legacyLines) {
                #expect(line.id == expected["id"] as? Int)
                #expect(line.voteCount == expected["voteCount"] as? Int)
                #expect(abs(line.percentage - (expected["percentage"] as? Double ?? .nan)) < 0.0001)
                // Deviation 2 (quirk Q9): legacy kept "N.<NBSP> " before the label.
                let legacyLabel = try #require(expected["label"] as? String)
                #expect(legacyLabel == "\(line.id).\u{00A0} \(line.label)")
            }
            #expect((legacy["options"] as? [Any])?.isEmpty == true)
            #expect(legacy["hiddenFields"] as? [String: String] == [:])
        }
        // Deviation 3: legacy found no footer (it looked for `div.sondageFooter`); the port reads the "Total" line of results.
        #expect(legacy["footer"] as? String == "")
        if case .results = poll.kind {
            #expect(poll.footer?.hasPrefix("Total : ") == true)
        } else {
            #expect(poll.footer == nil)
        }
    }
}
