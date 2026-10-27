import Foundation
import HFRModels
import Testing
@testable import HFRParsing

@Suite("Hop response classifier")
struct HopResponseParserTests {
    /// Captured write answers whose legacy classification the port keeps, except for the documented differences.
    static let oracleCases = [
        "W10", "W11", "W11x", "W12", "W13b", "W13c", "W13cx", "W14", "W14x", "W15",
        "W16a", "W16b", "W17a", "W17c", "W19", "W20a", "W20b"
    ]

    @Test("Differential: kind, message and anchor follow the legacy oracle", arguments: oracleCases)
    func followsOracle(id: String) throws {
        let oracle = try HopResponseOracle.load(id)
        let response = try HopResponseParser.classify(html: oracle.html)
        let legacyKind = try #require(oracle.legacy["classification"] as? String)
        // `loggedOut` refines the legacy "rejected" (W17c, difference 2 of the spec); nothing else changes kind.
        let expected: HopResponse.Kind = id == "W17c" ? .loggedOut : (legacyKind == "success" ? .success : .rejected)
        #expect(response.kind == expected)
        #expect(response.message == oracle.legacy["message"] as? String)
        guard response.kind == .success else {
            #expect(response.refreshURL == nil && response.refreshAnchor == nil)
            return
        }
        let legacyAnchor = try #require(oracle.legacy["anchor"] as? String)
        if oracle.flow == "delete" {
            // Legacy takes the deleted post from the request URL; the page carries no fragment (difference 3).
            #expect(response.refreshAnchor == nil)
        } else {
            #expect(response.refreshAnchor.map { "#" + $0 } ?? "" == legacyAnchor)
        }
    }

    @Test("W17b: the plain-text token refusal is a rejection, where legacy said success")
    func badTokenIsRejected() throws {
        let oracle = try HopResponseOracle.load("W17b")
        #expect(oracle.legacy["classification"] as? String == "success")
        #expect(oracle.legacy["hopFound"] as? Bool == false)
        let response = try HopResponseParser.classify(html: oracle.html)
        #expect(response.kind == .rejected)
        #expect(response.message == "Une erreur est survenue lors de l'envoi des données. Essayez de vider le cache de votre navigateur")
        #expect(response.refreshURL == nil)
    }

    @Test("W17c: a write sent without a session is loggedOut and keeps HFR's sentence")
    func loggedOut() throws {
        let response = try HopResponseParser.classify(html: Fixture.capture("W17c-mp-reply-logged-out-rejected"))
        #expect(response == HopResponse(kind: .loggedOut, message: "Désolé, vous devez être enregistré pour poster sur le forum"))
    }

    @Test("Flood refusals keep the sentence without the back link text")
    func floodMessageExcludesBackLink() throws {
        let reply = try HopResponseParser.classify(html: Fixture.capture("W20a-mp-reply-flood"))
        #expect(reply.kind == .rejected)
        #expect(reply.message == "Afin de prevenir les tentatives de flood, vous ne pouvez poster plus de 3 réponses consécutives"
            + " dans un intervalle de 10 minutes")
        let topic = try HopResponseParser.classify(html: Fixture.capture("W11x-mp-create-second-topic-flood"))
        #expect(topic.message?.hasSuffix("dans un intervalle de 60 minutes") == true)
    }

    @Test("Success resolves the refresh against the forum and keeps the fragment without #")
    func successRefresh() throws {
        let reply = try HopResponseParser.classify(html: Fixture.capture("W11-mp-reply-lf-legacy-success"))
        #expect(reply.refreshURL?.absoluteString == "https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=prive&post=3207033&page=1&p=1"
            + "&sondage=0&owntopic=0&trash=&trash_post=&print=0&numreponse=0&quote_only=0&new=0&nojs=0#bas")
        #expect(reply.refreshAnchor == "bas")
        let edit = try HopResponseParser.classify(html: Fixture.capture("W15-mp-edit-success"))
        #expect(edit.refreshAnchor == "t1980875030")
        let create = try HopResponseParser.classify(html: Fixture.capture("W10-mp-create-crlf-success"))
        #expect(create.refreshURL?.path == "/forum1.php")
        #expect(create.refreshAnchor == nil)
    }

    /// A captured GET write: file, sentence, refresh path (nil when the capture is not asserted on it).
    struct GetWrite: Sendable {
        let name: String
        let message: String
        let path: String?
    }

    @Test("GET writes (mark unread, flags) follow the same shape", arguments: [
        GetWrite(name: "W18-mp-mark-unread-success", message: "Le message a été marqué comme non lu avec succès",
                 path: "/forum1.php"),
        GetWrite(name: "P03a-addflag-success", message: "Favori positionné avec succès",
                 path: "/hfr/Discussions/Cuisine/liste_sujet-1.htm"),
        GetWrite(name: "P03b-addflag-again", message: "Favori positionné avec succès",
                 path: "/hfr/Discussions/Cuisine/liste_sujet-1.htm"),
        GetWrite(name: "P03d-delflag-favourite-success", message: "Drapeau effacé avec succès", path: nil)
    ])
    func getWrites(write: GetWrite) throws {
        let response = try HopResponseParser.classify(html: Fixture.capture(write.name))
        #expect(response.kind == .success)
        #expect(response.message == write.message)
        if let path = write.path { #expect(response.refreshURL?.path == path) }
        #expect(response.refreshURL?.host() == "forum.hardware.fr")
    }

    @Test("A read page with a .hop message is never a success (not a write answer: no refresh)", arguments: [
        ["R12-favourites-anon", "Aucun sujet que vous avez lu n'est connu"],
        ["RA5-mp-thread-after-delete-owner", "Ce message ne vous est pas destiné, désolé"]
    ])
    func readPagesAreNotSuccess(case pair: [String]) throws {
        let response = try HopResponseParser.classify(html: Fixture.capture(pair[0]))
        #expect(response == HopResponse(kind: .rejected, message: pair[1]))
    }

    /// Pages that refresh and carry a `.hop` sentence but are not write confirmations.
    static let refreshingNonWrites = [
        "W01-login-failure", "W01b-login-success-user1", "W03-login-success", "R08-1-list-cat13-owntopic1-empty",
        "R08-3-list-cat13-owntopic3-empty", "R50a-search-post-waiting-page"
    ]

    @Test("Refresh plus a .hop sentence is not a confirmation: login, empty list, search wait are never success",
          arguments: refreshingNonWrites)
    func refreshingPagesAreNotSuccess(name: String) throws {
        #expect(try HopResponseParser.classify(html: Fixture.capture(name)).kind != .success)
    }

    /// Every capture whose classification is success, under `.write`: the write confirmations and nothing else.
    static let writeConfirmations: Set<String> = [
        "W10-mp-create-crlf-success", "W11-mp-reply-lf-legacy-success", "W12-mp-reply-nonbmp-success",
        "W13b-mp-reply-browser-semantics-success", "W13c-mp-reply-recipient-success", "W14-mp-reply-multiquote-success",
        "W15-mp-edit-success", "W16a-mp-delete-post-success", "W16b-mp-delete-post-again", "W19-mp-delete-first-post-success",
        "W18-mp-mark-unread-success", "P03a-addflag-success", "P03b-addflag-again", "P03d-delflag-favourite-success"
    ]

    @Test("Sweep: across the whole capture corpus only the write confirmations classify as success")
    func corpusSweep() throws {
        let url = try #require(Bundle.module.url(forResource: "captures", withExtension: nil, subdirectory: "Fixtures"))
        let names = try FileManager.default.contentsOfDirectory(atPath: url.path)
            .filter { $0.hasSuffix(".html") }.map { String($0.dropLast(5)) }
        #expect(names.count > 50)
        var successes: Set<String> = []
        for name in names where try HopResponseParser.classify(html: Fixture.capture(name)).kind == .success {
            successes.insert(name)
        }
        #expect(successes == Self.writeConfirmations)
    }

    @Test("A sentence split by a nested element is read whole: the logged-out marker inside <b> still counts")
    func nestedSentence() throws {
        let html = page(hop: "Désolé, vous devez <b>être enregistré</b> pour poster <a href=\"/\">Retour</a>")
        let response = try HopResponseParser.classify(html: html)
        #expect(response == HopResponse(kind: .loggedOut, message: "Désolé, vous devez être enregistré pour poster"))
    }

    @Test("A page without .hop (the edit form R44) is unrecognized")
    func formPageIsUnrecognized() throws {
        let response = try HopResponseParser.classify(html: Fixture.capture("R44-mp-edit-form-other-account-message"))
        #expect(response == HopResponse(kind: .unrecognized))
    }

    @Test("Alert prepare: the form page (R46) is not 'already alerted'")
    func alertFormIsNotAlreadyAlerted() throws {
        let response = try HopResponseParser.classify(html: Fixture.capture("R46-modo-alert-form"), context: .alertPrepare)
        #expect(response == HopResponse(kind: .unrecognized))
    }

    // MARK: - Shapes no capture shows (derived from the legacy rules, labelled in the spec as pending capture)

    private func page(head: String = "", hop: String) -> String {
        "<html><head>\(head)</head><body><div class=\"mesdiscussions\"><div class=\"hop\">\(hop)</div></div></body></html>"
    }

    private let refresh = "<meta http-equiv=\"Refresh\" content=\"1; url=/forum1.php?config=hfr.inc&amp;cat=13\" />"

    @Test("Alert prepare: a .hop with a link or an input is 'already alerted' (legacy rule, text not captured)")
    func alreadyAlerted() throws {
        let link = page(hop: "Placeholder alert page text <a href=\"javascript:history.back(1)\">Retour</a>")
        let response = try HopResponseParser.classify(html: link, context: .alertPrepare)
        #expect(response == HopResponse(kind: .alreadyAlerted, message: "Placeholder alert page text"))
        let input = page(hop: "x <input type=\"submit\" value=\"Retour\">")
        #expect(try HopResponseParser.classify(html: input, context: .alertPrepare).kind == .alreadyAlerted)
        // The same shape in a submitted write is a refusal.
        #expect(try HopResponseParser.classify(html: link, context: .write).kind == .rejected)
    }

    @Test("Alert prepare never reports success")
    func alertPrepareNeverSucceeds() throws {
        let html = page(head: refresh, hop: "Placeholder text")
        #expect(try HopResponseParser.classify(html: html, context: .alertPrepare).kind == .unrecognized)
    }

    @Test("A .hop without refresh is not confirmed")
    func hopWithoutRefresh() throws {
        let response = try HopResponseParser.classify(html: page(hop: "Votre message a été posté avec succès !"))
        #expect(response == HopResponse(kind: .unrecognized, message: "Votre message a été posté avec succès !"))
    }

    @Test("A refresh without .hop is not confirmed")
    func refreshWithoutHop() throws {
        let html = "<html><head>\(refresh)</head><body>ok</body></html>"
        #expect(try HopResponseParser.classify(html: html) == HopResponse(kind: .unrecognized))
    }

    @Test("A refresh next to a .hop link is a refusal (legacy rule, difference from the live service)")
    func refreshWithLinkIsRejected() throws {
        let html = page(head: refresh, hop: "Refusé <a href=\"/\">Retour</a>")
        let response = try HopResponseParser.classify(html: html)
        #expect(response == HopResponse(kind: .rejected, message: "Refusé"))
    }

    @Test("A refresh that leaves the forum is not a confirmation", arguments: [
        "https://evil.example/forum1.php", "//evil.example/x", "http://forum.hardware.fr:80/forum1.php", "javascript:alert(1)",
        "https://forum.hardware.fr:8443/forum1.php"
    ])
    func offForumRefresh(target: String) throws {
        let head = "<meta http-equiv=\"refresh\" content=\"1; url=\(target)\">"
        let response = try HopResponseParser.classify(html: page(head: head, hop: "Votre message a été posté avec succès !"))
        #expect(response.kind == .unrecognized)
        #expect(response.refreshURL == nil)
    }

    @Test("A relative refresh is resolved against the request URL")
    func relativeAgainstRequest() throws {
        let head = "<meta http-equiv=\"refresh\" content=\"1; url=forum2.php?post=1#t5\">"
        let request = try #require(URL(string: "https://forum.hardware.fr/user/nonlu.php?post=1"))
        let response = try HopResponseParser.classify(html: page(head: head, hop: "ok avec succès"), requestURL: request)
        #expect(response.refreshURL?.absoluteString == "https://forum.hardware.fr/user/forum2.php?post=1#t5")
        #expect(response.refreshAnchor == "t5")
    }

    @Test("Empty and unrelated bodies are unrecognized, never success", arguments: ["", "   ", "<html></html>", "OK", "Erreur"])
    func emptyBodies(html: String) throws {
        #expect(try HopResponseParser.classify(html: html).kind == .unrecognized)
    }

    @Test("An empty .hop has no message and is not a success")
    func emptyHop() throws {
        let response = try HopResponseParser.classify(html: page(head: refresh, hop: ""))
        #expect(response == HopResponse(kind: .unrecognized))
    }
}
