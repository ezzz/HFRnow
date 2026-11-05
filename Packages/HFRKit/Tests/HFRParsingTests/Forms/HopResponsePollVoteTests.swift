import Foundation
import HFRModels
import Testing
@testable import HFRParsing

/// LOT-054 (#395): the poll vote answers `W42`-`W44` under `Context.pollVote`, and the vote sentence nowhere else.
@Suite("Hop response classifier: poll vote")
struct HopResponsePollVoteTests {
    /// Every capture whose classification is success under `.pollVote`: the vote confirmation and nothing else.
    static let pollVoteConfirmations: Set<String> = ["W42-poll-vote-success"]

    @Test("Sweep: across the whole capture corpus only the vote confirmation classifies as success under .pollVote")
    func pollVoteCorpusSweep() throws {
        var successes: Set<String> = []
        for name in try Self.corpus() where try HopResponseParser.classify(
            html: Fixture.capture(name), context: .pollVote
        ).kind == .success {
            successes.insert(name)
        }
        #expect(successes == Self.pollVoteConfirmations)
    }

    @Test("Sweep: no capture is a success before the alert form (.alertPrepare)")
    func alertPrepareCorpusSweep() throws {
        for name in try Self.corpus() {
            #expect(try HopResponseParser.classify(html: Fixture.capture(name), context: .alertPrepare).kind != .success, "\(name)")
        }
    }

    private static func corpus() throws -> [String] {
        let url = try #require(Bundle.module.url(forResource: "captures", withExtension: nil, subdirectory: "Fixtures"))
        return try FileManager.default.contentsOfDirectory(atPath: url.path)
            .filter { $0.hasSuffix(".html") }.map { String($0.dropLast(5)) }
    }

    @Test("W42: the vote confirmation is a success under .pollVote, with HFR's sentence and the topic page as refresh")
    func pollVoteConfirmed() throws {
        let vote = try #require(URL(string: "https://forum.hardware.fr/user/vote.php?config=hfr.inc"))
        let response = try HopResponseParser.classify(
            html: Fixture.capture("W42-poll-vote-success"), context: .pollVote, requestURL: vote
        )
        #expect(response.kind == .success)
        #expect(response.message == "Votre vote a bien été pris en compte !")
        #expect(response.refreshURL?.absoluteString == "https://forum.hardware.fr/hfr/Programmation/iOS/sujet_9900002_1.htm")
        #expect(response.refreshAnchor == nil)
        // The same page answering another write is not a confirmation: it lacks "avec succès".
        #expect(try HopResponseParser.classify(html: Fixture.capture("W42-poll-vote-success")).kind == .unrecognized)
    }

    @Test("W43, W44: a second vote is a refusal under .pollVote, keeping HFR's sentence", arguments: [
        "W43-poll-vote-already-voted", "W44-poll-vote-linked-account-already-voted"
    ])
    func pollVoteAlreadyVoted(name: String) throws {
        let response = try HopResponseParser.classify(html: Fixture.capture(name), context: .pollVote)
        #expect(response == HopResponse(kind: .rejected, message: "Désolé, vous avez déjà voté !"))
    }

    @Test("Under .pollVote a write confirmation is not a vote's, and the vote sentence needs the refresh", arguments: [
        "W30-public-reply-success", "P03a-addflag-success", "W41-public-first-post-edit-add-poll-success"
    ])
    func writeConfirmationIsNotAVote(name: String) throws {
        #expect(try HopResponseParser.classify(html: Fixture.capture(name), context: .pollVote).kind == .unrecognized)
    }

    @Test("Under .pollVote the vote sentence must be whole, affirmative, link-less and with a forum refresh")
    func pollVoteShapes() throws {
        let topic = "<meta http-equiv=\"Refresh\" content=\"1; url=/hfr/Programmation/iOS/sujet_9900002_1.htm\" />"
        let sentence = "Votre vote a bien été pris en compte !"
        #expect(try HopResponseParser.classify(html: Self.page(head: topic, hop: sentence), context: .pollVote).kind == .success)
        // Derived from W42: no refresh, another sentence, a prefix or a refresh off the forum.
        #expect(try HopResponseParser.classify(html: Self.page(hop: sentence), context: .pollVote).kind == .unrecognized)
        #expect(try HopResponseParser.classify(
            html: Self.page(head: topic, hop: "Votre vote n'a pas été pris en compte !"), context: .pollVote
        ).kind == .unrecognized)
        #expect(try HopResponseParser.classify(
            html: Self.page(head: topic, hop: "Erreur : " + sentence), context: .pollVote
        ).kind == .unrecognized)
        let away = "<meta http-equiv=\"Refresh\" content=\"1; url=https://example.com/\" />"
        #expect(try HopResponseParser.classify(html: Self.page(head: away, hop: sentence), context: .pollVote).kind == .unrecognized)
        let link = Self.page(head: topic, hop: sentence + " <a href=\"javascript:history.back(1)\">Retour</a>")
        #expect(try HopResponseParser.classify(html: link, context: .pollVote).kind == .rejected)
    }

    private static func page(head: String = "", hop: String) -> String {
        "<html><head>\(head)</head><body><div class=\"mesdiscussions\"><div class=\"hop\">\(hop)</div></div></body></html>"
    }
}
