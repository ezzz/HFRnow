import Foundation
import HFRModels
import HFRNetwork
import Testing
@testable import HFRClient

/// Every way a write ends without HFR's confirmation: refused locally (nothing sent), refused by HFR (captured answers),
/// or of unknown outcome (never reported as success, never resent).
@Suite("Posting flow: refusals and unknown outcomes")
struct PostingRefusalTests {
    private static let reply: PostingHarness.Write = { flow, form async throws(PostingError) in
        try await flow.reply("a reply", with: form)
    }

    // MARK: - HFR's refusals (captured answers)

    @Test("Captured refusals are reported with HFR's sentence", arguments: ["W17b", "W20a", "W20b", "W14x", "W13cx"])
    func capturedRefusals(answerID: String) async throws {
        let outcome = try await PostingHarness.run(form: "R47b", answer: answerID, write: Self.reply)
        guard case let .rejected(message) = outcome.error else {
            Issue.record("expected a refusal, got \(String(describing: outcome.result))")
            return
        }
        #expect(message?.isEmpty == false)
        #expect(outcome.requests.count == 2)
    }

    @Test("W11x: the new-thread flood refusal")
    func newThreadFlood() async throws {
        let outcome = try await PostingHarness.run(form: "R45b", answer: "W11x") { flow, form async throws(PostingError) in
            try await flow.newPrivateMessage(to: "user1", subject: "s", text: "t", with: form)
        }
        guard case let .rejected(message) = outcome.error else {
            Issue.record("expected a refusal")
            return
        }
        #expect(message?.contains("60 minutes") == true)
    }

    @Test("W17c: a write HFR refuses as logged out")
    func loggedOutAnswer() async throws {
        let outcome = try await PostingHarness.run(form: "R47b", answer: "W17c", write: Self.reply)
        #expect(outcome.error == .notLoggedIn)
    }

    // MARK: - Unknown outcomes

    @Test("Another write's confirmation is not this write's success")
    func unexpectedConfirmation() async throws {
        let outcome = try await PostingHarness.run(form: "R47b", answer: "W15", write: Self.reply)
        #expect(outcome.error == .unconfirmed(.unexpectedConfirmation(message: "Votre message a été édité avec succès !")))
        // W18 (mark unread) is a confirmation too, of another action.
        let unread = Result<HTTPResponse, NetworkError>.success(
            try Capture.response(
                "W18-mp-mark-unread-success", url: PostingCapture.url("https://forum.hardware.fr/bddpost.php?config=hfr.inc")
            )
        )
        let other = await PostingHarness.run(
            formPage: try PostingCapture.form("R47b"), formURL: try PostingCapture.pageURL("R47b"), answer: unread, write: Self.reply
        )
        guard case .unconfirmed(.unexpectedConfirmation) = other.error else {
            Issue.record("expected an unexpected confirmation, got \(String(describing: other.error))")
            return
        }
    }

    @Test(
        "A page that is neither a confirmation nor a refusal is unconfirmed",
        arguments: ["W01-login-failure", "R47b-mp-reply-composer", "R08-1-list-cat13-owntopic1-empty"]
    )
    func unrecognizedAnswer(page: String) async throws {
        let answer = Result<HTTPResponse, NetworkError>.success(
            try Capture.response(page, url: PostingCapture.url("https://forum.hardware.fr/bddpost.php?config=hfr.inc"))
        )
        let outcome = await PostingHarness.run(
            formPage: try PostingCapture.form("R47b"), formURL: try PostingCapture.pageURL("R47b"), answer: answer, write: Self.reply
        )
        guard case .unconfirmed(.unrecognizedAnswer) = outcome.error else {
            Issue.record("expected an unrecognized answer, got \(String(describing: outcome.error))")
            return
        }
    }

    @Test(
        "A failed POST exchange is unconfirmed, sent once",
        arguments: [NetworkError.timedOut, .offline, .cancelled, .transport(code: -1005)]
    )
    func failedPost(error: NetworkError) async throws {
        let outcome = await PostingHarness.run(
            formPage: try PostingCapture.form("R47b"), formURL: try PostingCapture.pageURL("R47b"), answer: .failure(error),
            write: Self.reply
        )
        #expect(outcome.error == .unconfirmed(.transport(error)))
        #expect(outcome.requests.filter { $0.method == .post }.count == 1)
    }

    @Test("A POST the session refuses to send is a plain failure: nothing left the device")
    func postRefusedBySession() async throws {
        let outcome = await PostingHarness.run(
            formPage: try PostingCapture.form("R47b"), formURL: try PostingCapture.pageURL("R47b"),
            answer: .failure(.invalidRequest(reason: "host")), write: Self.reply
        )
        #expect(outcome.error == .network(.invalidRequest(reason: "host")))
    }

    @Test("An HTTP error answer to the POST is unconfirmed")
    func httpErrorAfterPost() async throws {
        let url = PostingCapture.url("https://forum.hardware.fr/bddpost.php?config=hfr.inc")
        let outcome = await PostingHarness.run(
            formPage: try PostingCapture.form("R47b"), formURL: try PostingCapture.pageURL("R47b"),
            answer: .success(HTTPResponse(statusCode: 500, url: url)), write: Self.reply
        )
        #expect(outcome.error == .unconfirmed(.transport(.httpStatus(code: 500, url: url))))
    }

    @Test("A redirect answer to the POST is not followed and is unconfirmed")
    func redirectAfterPost() async throws {
        let url = PostingCapture.url("https://forum.hardware.fr/bddpost.php?config=hfr.inc")
        let redirect = HTTPResponse(statusCode: 302, headers: ["Location": "/"], url: url)
        let outcome = await PostingHarness.run(
            formPage: try PostingCapture.form("R47b"), formURL: try PostingCapture.pageURL("R47b"), answer: .success(redirect),
            write: Self.reply
        )
        #expect(outcome.error == .unconfirmed(.unrecognizedAnswer(message: nil)))
        #expect(outcome.requests.count == 2)
    }

    // MARK: - Form page

    @Test("R40b: the anonymous composer is refused before any POST")
    func anonymousComposer() async throws {
        let outcome = try await PostingHarness.run(form: "R40b", write: Self.reply)
        #expect(outcome.error == .notLoggedIn)
        #expect(outcome.requests.count == 1)
        #expect(outcome.hashChecks.isEmpty)
    }

    @Test("A composer with an empty token is not logged in, even with a pseudo")
    func emptyToken() async throws {
        let page = try PostingHarness.editedForm("R47b") {
            $0.replacing("name=\"hash_check\" value=\"REDACTED\"", with: "name=\"hash_check\" value=\"\"")
        }
        let outcome = await PostingHarness.run(formPage: page, formURL: try PostingCapture.pageURL("R47b"), write: Self.reply)
        #expect(outcome.error == .notLoggedIn)
        #expect(outcome.requests.count == 1)
    }

    @Test("A page without the form reports its .hop sentence (RA5), or a logged-out session (W17c)")
    func pageWithoutForm() async throws {
        let url = PostingCapture.url("https://forum.hardware.fr/message.php?config=hfr.inc&cat=prive&post=1")
        let notForYou = await PostingHarness.run(
            formPage: .success(try Capture.response("RA5-mp-thread-after-delete-owner", url: url)), formURL: url, write: Self.reply
        )
        #expect(notForYou.error == .formUnavailable(message: "Ce message ne vous est pas destiné, désolé"))
        let loggedOut = await PostingHarness.run(
            formPage: .success(try Capture.response("W17c-mp-reply-logged-out-rejected", url: url)), formURL: url, write: Self.reply
        )
        #expect(loggedOut.error == .notLoggedIn)
        #expect(loggedOut.requests.count == 1)
    }

    @Test("A failed form request is a network error and nothing is posted")
    func formRequestFails() async throws {
        let url = try PostingCapture.pageURL("R47b")
        let outcome = await PostingHarness.run(formPage: .failure(.timedOut), formURL: url, write: Self.reply)
        #expect(outcome.error == .network(.timedOut))
        #expect(outcome.requests.count == 1)
    }

    @Test(
        "Form URLs off the forum are refused before any request",
        arguments: [
            "http://forum.hardware.fr/message.php", "https://forum.hardware.fr:8443/message.php",
            "https://evil.example/message.php", "https://user@forum.hardware.fr/message.php", "https://www.hardware.fr/message.php"
        ]
    )
    func offForumFormURL(raw: String) async throws {
        let outcome = await PostingHarness.run(
            formPage: try PostingCapture.form("R47b"), formURL: PostingCapture.url(raw), write: Self.reply
        )
        #expect(outcome.error == .invalidFormURL)
        #expect(outcome.requests.isEmpty)
    }

    @Test(
        "A form whose action is absent or leaves the forum is never posted",
        arguments: ["", " action=\"https://evil.example/bddpost.php\"", " action=\"http://forum.hardware.fr:80/bddpost.php\""]
    )
    func missingAction(action: String) async throws {
        let page = try PostingHarness.editedForm("R47b") {
            $0.replacing(
                "<form name=\"hop\" id=\"hop\" action=\"/bddpost.php?config=hfr.inc\"", with: "<form name=\"hop\" id=\"hop\"\(action)"
            )
        }
        let outcome = await PostingHarness.run(formPage: page, formURL: try PostingCapture.pageURL("R47b"), write: Self.reply)
        #expect(outcome.error == .missingAction)
        #expect(outcome.requests.count == 1)
    }
}
