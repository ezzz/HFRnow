import Foundation
import HFRModels
import HFRNetwork
import Testing
@testable import HFRClient

/// Differential tests against the captured writes: the form page HFR served (`R4x`), the flow fills and submits it, and
/// the body must be the one captured in `W10`-`W19` (`request_body`), read with browser semantics: legacy's `"0"` for
/// unchecked boxes dropped, line breaks CRLF. The captured answer must then come back as this write's success.
@Suite("Posting flow: captured writes")
struct PostingCaptureTests {
    private static let boxes: Set<String> = ["signature", "smiley", "emaill", "delete"]
    private static let postURL = "https://forum.hardware.fr/bddpost.php?config=hfr.inc"
    private static let editURL = "https://forum.hardware.fr/bdd.php?config=hfr.inc"

    private func expectPost(_ outcome: PostingHarness.Outcome, to url: String, body answerID: String) throws {
        let post = try #require(outcome.post)
        #expect(outcome.requests.count == 2)
        #expect(post.url.absoluteString == url)
        #expect(post.headers["Content-Type"] == "application/x-www-form-urlencoded; charset=utf-8")
        #expect(post.redirectPolicy == .doNotFollow)
        #expect(post.timeout == PostingFlow.postTimeout)
        #expect(outcome.body == (try PostingHarness.browserBody(of: answerID, checkboxes: Self.boxes)))
        #expect(outcome.hashChecks == ["REDACTED"])
    }

    @Test("W10: new private message from R45b, CRLF text")
    func newPrivateMessage() async throws {
        let text = "fixture-test 1, line 1 (CRLF)\nline 2"
        let outcome = try await PostingHarness.run(form: "R45b", answer: "W10") { flow, form async throws(PostingError) in
            try await flow.newPrivateMessage(to: "user1", subject: "fixture-test-1", text: text, with: form)
        }
        try expectPost(outcome, to: Self.postURL, body: "W10")
        let result = try outcome.result.get()
        #expect(result.action == .newPrivateMessage)
        #expect(result.message == "Votre message a été posté avec succès !")
        #expect(result.refreshAnchor == nil)
        #expect(result.postNumber == nil)
    }

    @Test("W11: reply from R47b; the captured bare LF is sent as CRLF")
    func reply() async throws {
        let outcome = try await PostingHarness.run(form: "R47b", answer: "W11") { flow, form async throws(PostingError) in
            try await flow.reply("fixture-test 2, line 1 (LF) :)\nline 2", with: form)
        }
        try expectPost(outcome, to: Self.postURL, body: "W11")
        #expect(outcome.body?.contains("%0D%0Aline+2") == true)
        let result = try outcome.result.get()
        #expect(result.message == "Votre réponse a été postée avec succès !")
        #expect(result.refreshAnchor == "bas")
        #expect(result.refreshURL.host() == "forum.hardware.fr")
    }

    @Test("W13b: reply with browser semantics and the smiley box checked is byte-identical to the capture")
    func replyBrowserSemantics() async throws {
        let outcome = try await PostingHarness.run(form: "R47b", answer: "W13b") { flow, form async throws(PostingError) in
            try await flow.reply(
                "fixture-test 4, browser semantics, smiley box checked :)", options: [.disablesSmileys: true], with: form
            )
        }
        #expect(outcome.body == (try Capture.meta("W13b").requestBody))
        #expect(try outcome.result.get().action == .reply)
    }

    @Test("W13c: the recipient's reply from R47u1 with the signature box")
    func replyWithSignature() async throws {
        let outcome = try await PostingHarness.run(form: "R47u1", answer: "W13c") { flow, form async throws(PostingError) in
            try await flow.reply("fixture-test 6, reply from user1", options: [.signature: true], with: form)
        }
        try expectPost(outcome, to: Self.postURL, body: "W13c")
        #expect(outcome.body?.contains("pseudo=user1") == true)
        #expect(outcome.error == nil)
    }

    @Test("W14: multi-quote prefill of R47c posted as served")
    func multiQuote() async throws {
        let outcome = try await PostingHarness.run(form: "R47c", answer: "W14") { flow, form async throws(PostingError) in
            try await flow.reply(form.form.textareaContent ?? "", with: form)
        }
        try expectPost(outcome, to: Self.postURL, body: "W14")
        #expect(outcome.error == nil)
    }

    @Test("W15: edit of a later post from R43b; no delete field is sent")
    func edit() async throws {
        let outcome = try await PostingHarness.run(form: "R43b", answer: "W15") { flow, form async throws(PostingError) in
            try await flow.edit("fixture-test 2, edited (W15)", with: form)
        }
        try expectPost(outcome, to: Self.editURL, body: "W15")
        #expect(outcome.body?.contains("delete") == false)
        let result = try outcome.result.get()
        #expect(result.message == "Votre message a été édité avec succès !")
        #expect(result.refreshAnchor == "t1980875030")
        #expect(result.postNumber == 1_980_875_030)
    }

    @Test("W16a: delete of a later post from R43c sends the stored text back with delete=1")
    func deleteLaterPost() async throws {
        let outcome = try await PostingHarness.run(form: "R43c", answer: "W16a") { flow, form async throws(PostingError) in
            #expect(!form.deletesWholeTopic)
            return try await flow.delete(with: form)
        }
        try expectPost(outcome, to: Self.editURL, body: "W16a")
        let result = try outcome.result.get()
        #expect(result.message == "Message effacé avec succès !")
        #expect(result.refreshAnchor == nil)
        #expect(result.postNumber == 1_980_875_031)
    }

    @Test("W19: delete of the first post from R43a deletes the thread once confirmed")
    func deleteWholeThread() async throws {
        let outcome = try await PostingHarness.run(form: "R43a", answer: "W19") { flow, form async throws(PostingError) in
            #expect(form.deletesWholeTopic)
            return try await flow.delete(with: form, confirmingWholeTopic: true)
        }
        try expectPost(outcome, to: Self.editURL, body: "W19")
        #expect(try outcome.result.get().action == .delete)
    }

    @Test("Edit of the first post from R43a may rename the thread")
    func editFirstPostSubject() async throws {
        let outcome = try await PostingHarness.run(form: "R43a", answer: "W15") { flow, form async throws(PostingError) in
            try await flow.edit("new text", subject: "renamed", with: form)
        }
        let pairs = PostingHarness.pairs(of: try #require(outcome.body))
        #expect(pairs.filter { $0.name == "sujet" }.map(\.value) == ["renamed"])
        #expect(outcome.error == nil)
    }

    @Test("New topic from R45a: subject and sub-category written at their places in document order")
    func newTopic() async throws {
        // No public new-topic answer is captured: the MP creation answer (same sentence) stands in for HFR's reply.
        let outcome = try await PostingHarness.run(form: "R45a", answer: "W10") { flow, form async throws(PostingError) in
            let subcategory = form.form.subcategories.last?.value ?? ""
            return try await flow.newTopic(subject: "a subject", subcategory: subcategory, text: "text", with: form)
        }
        let names = PostingHarness.pairs(of: try #require(outcome.body)).map(\.name)
        let expected = [
            "hash_check", "parents", "post", "stickold", "new", "cat", "numreponse", "numrep", "page", "verifrequet", "p",
            "sondage", "sond", "cache", "owntopic", "config", "pseudo", "password", "sujet", "toread1", "toread2", "toread3",
            "toread4", "toread5", "subcat", "MsgIcon", "search_smilies", "ColorUsedMem", "content_form", "wysiwyg", "submit"
        ]
        #expect(names == expected)
        #expect(outcome.body?.contains("sujet=a+subject") == true)
        #expect(try outcome.result.get().action == .newTopic)
    }
}
