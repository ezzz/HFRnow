import Foundation
import HFRModels
import Testing
@testable import HFRParsing

/// #395: the moderator alert answers `W46`, `W47`, `R88`, `R89` under `Context.alertPrepare` and `.alertSubmit`, and the
/// alert sentences nowhere else.
@Suite("Hop response classifier: moderator alert")
struct HopResponseAlertTests {
    /// Every capture whose classification is success under `.alertSubmit`: the alert confirmation and nothing else.
    static let alertConfirmations: Set<String> = ["W46-modo-alert-success"]

    private static let confirmation = "Un message a été envoyé avec succès aux modérateurs"
    private static let loggedOut = "Vous devez être identifié pour prévenir les modérateurs"
    private static let contexts: [HopResponseParser.Context] = [.write, .pollVote, .alertPrepare, .alertSubmit]

    @Test("Sweep: across the whole capture corpus only the alert confirmation classifies as success under .alertSubmit")
    func alertSubmitCorpusSweep() throws {
        var successes: Set<String> = []
        for name in try Self.corpus() where try HopResponseParser.classify(
            html: Fixture.capture(name), context: .alertSubmit
        ).kind == .success {
            successes.insert(name)
        }
        #expect(successes == Self.alertConfirmations)
    }

    @Test("W46: the alert confirmation is a success under .alertSubmit, with HFR's sentence and nothing to follow")
    func alertConfirmed() throws {
        let response = try HopResponseParser.classify(html: Fixture.capture("W46-modo-alert-success"), context: .alertSubmit)
        #expect(response == HopResponse(kind: .success, message: Self.confirmation))
    }

    @Test("W46 is never a success outside .alertSubmit")
    func alertSentenceOutsideItsContext() throws {
        let html = try Fixture.capture("W46-modo-alert-success")
        #expect(try HopResponseParser.classify(html: html, context: .write) == HopResponse(kind: .rejected, message: Self.confirmation))
        #expect(try HopResponseParser.classify(html: html, context: .pollVote).kind == .rejected)
        #expect(try HopResponseParser.classify(html: html, context: .alertPrepare).kind == .alreadyAlerted)
    }

    @Test("R89, W47: HFR's alert sentence for a missing session is loggedOut in the alert contexts only", arguments: [
        "R89-modo-alert-page-logged-out", "W47-modo-alert-logged-out-rejected"
    ])
    func alertLoggedOut(name: String) throws {
        let html = try Fixture.capture(name)
        for context in [HopResponseParser.Context.alertPrepare, .alertSubmit] {
            #expect(try HopResponseParser.classify(html: html, context: context) == HopResponse(kind: .loggedOut, message: Self.loggedOut))
        }
        // Not captured after another write: there it stays the plain refusal it looks like.
        for context in [HopResponseParser.Context.write, .pollVote] {
            #expect(try HopResponseParser.classify(html: html, context: context).kind == .rejected)
        }
    }

    @Test("R88: a message already reported is alreadyAlerted before the form, a refusal after a submit, never a success")
    func alreadyReported() throws {
        let html = try Fixture.capture("R88-modo-alert-already-reported")
        let sentence = "Votre demande de modération sur ce message n'est pas encore traitée."
        #expect(try HopResponseParser.classify(html: html, context: .alertPrepare) == HopResponse(kind: .alreadyAlerted, message: sentence))
        #expect(try HopResponseParser.classify(html: html, context: .alertSubmit) == HopResponse(kind: .rejected, message: sentence))
    }

    @Test("Under .alertSubmit a write or vote confirmation is not an alert's", arguments: [
        "W10-mp-create-crlf-success", "W30-public-reply-success", "P03a-addflag-success", "W42-poll-vote-success"
    ])
    func otherConfirmationsAreNotAnAlert(name: String) throws {
        let response = try HopResponseParser.classify(html: Fixture.capture(name), context: .alertSubmit)
        #expect(response.kind == .unrecognized)
        #expect(response.refreshURL == nil)
    }

    @Test("Under .alertSubmit the logged-out sentence of W17c and the token refusal of W17b keep their reading")
    func sharedRefusals() throws {
        #expect(try HopResponseParser.classify(
            html: Fixture.capture("W17c-mp-reply-logged-out-rejected"), context: .alertSubmit
        ).kind == .loggedOut)
        #expect(try HopResponseParser.classify(
            html: Fixture.capture("W17b-mp-reply-bad-token-rejected"), context: .alertSubmit
        ).kind == .rejected)
    }

    // MARK: - Shapes derived from W46 (not captured)

    private static let back =
        " <br /><br /><a href=\"javascript:history.back(1)\" class=\"Topic\"><b>Retour à la page précédente</b></a>"
    private static let refresh = "<meta http-equiv=\"Refresh\" content=\"1; url=/forum1.php?config=hfr.inc&amp;cat=13\" />"

    @Test("The alert sentence link-less with a forum refresh is no success in any context (it says 'avec succès')")
    func linklessAlertSentence() throws {
        let html = Self.page(head: Self.refresh, hop: Self.confirmation)
        for context in Self.contexts {
            #expect(try HopResponseParser.classify(html: html, context: context).kind == .unrecognized, "\(context)")
        }
    }

    @Test("Under .alertSubmit the confirmation must be whole: a prefix, a negation or another sentence is a refusal",
          arguments: [
            "Erreur : " + confirmation, "Aucun message n'a été envoyé avec succès aux modérateurs",
            confirmation + " ?", "Un message a été envoyé avec succès"
          ])
    func alertSentenceMustBeWhole(sentence: String) throws {
        let response = try HopResponseParser.classify(html: Self.page(hop: sentence + Self.back), context: .alertSubmit)
        #expect(response.kind == .rejected)
    }

    @Test("Under .alertSubmit the vote sentence is not an alert's, with or without a back link")
    func voteSentenceIsNotAnAlert() throws {
        let vote = "Votre vote a bien été pris en compte !"
        #expect(try HopResponseParser.classify(html: Self.page(hop: vote + Self.back), context: .alertSubmit).kind == .rejected)
        #expect(try HopResponseParser.classify(
            html: Self.page(head: Self.refresh, hop: vote), context: .alertSubmit
        ).kind == .unrecognized)
    }

    private static func page(head: String = "", hop: String) -> String {
        "<html><head>\(head)</head><body><div class=\"mesdiscussions\"><div class=\"hop\">\(hop)</div></div></body></html>"
    }

    private static func corpus() throws -> [String] {
        let url = try #require(Bundle.module.url(forResource: "captures", withExtension: nil, subdirectory: "Fixtures"))
        return try FileManager.default.contentsOfDirectory(atPath: url.path)
            .filter { $0.hasSuffix(".html") }.map { String($0.dropLast(5)) }
    }
}
