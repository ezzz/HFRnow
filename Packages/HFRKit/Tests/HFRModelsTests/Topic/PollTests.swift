import Testing
@testable import HFRModels

@Suite struct PollTests {
    private let options = [
        PollOption(id: 1, text: "Oui", fieldName: "reponse1"),
        PollOption(id: 2, text: "Non", fieldName: "reponse2")
    ]

    @Test func votablePollRoundTripsWithHiddenFields() throws {
        let poll = Poll(
            question: "Q?",
            footer: "fin",
            maxChoices: 2,
            kind: .votable(options: options, hiddenFields: ["hash_check": "x", "cat": "13"])
        )
        let decoded = try roundTrip(poll)
        #expect(decoded == poll)
        guard case .votable(let decodedOptions, let fields) = decoded.kind else {
            Issue.record("expected a votable poll")
            return
        }
        #expect(decodedOptions.map(\.id) == [1, 2])
        #expect(fields["cat"] == "13")
    }

    @Test func resultsPollKeepsDecimalPercentages() throws {
        let poll = Poll(question: "Q", kind: .results([PollResult(id: 1, label: "A", percentage: 16.7, voteCount: 5)]))
        let decoded = try roundTrip(poll)
        guard case .results(let lines) = decoded.kind else {
            Issue.record("expected results")
            return
        }
        #expect(lines.first?.percentage == 16.7)
    }

    @Test func votableAndResultsAreDifferent() {
        #expect(Poll(question: "Q", kind: .results([])) != Poll(question: "Q", kind: .votable(options: [], hiddenFields: [:])))
    }

    @Test func maxChoicesIsFlooredAtOne() {
        #expect(Poll(question: "Q", maxChoices: 0, kind: .results([])).maxChoices == 1)
        #expect(Poll(question: "Q", kind: .results([])).maxChoices == 1)
    }

    @Test func optionAndResultIdentitiesAreTheirPositions() {
        #expect(options.map(\.id) == [1, 2])
        #expect(PollResult(id: 3, label: "", percentage: 0, voteCount: 0).id == 3)
    }
}
