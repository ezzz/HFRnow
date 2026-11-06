import Foundation
import HFRModels
import HFRNetwork
import HFRParsing
import Testing
@testable import HFRClient

/// LOT-050 `submit`: `R46`'s form posted like a browser (the LOT-004 oracle's fields, `raison` filled), once, never
/// retried; HFR's answer is read by LOT-037 `.alertSubmit` (#395): its confirmation (`W46`) is the only success, its
/// logged-out sentence (`W47`) is `notLoggedIn`, the other captured `.hop` refusals are `rejected`.
@Suite("Moderator alert: submit")
struct ModeratorAlertSubmitTests {
    private static func answer(_ id: String) throws -> Result<HTTPResponse, NetworkError> {
        try PostingCapture.answer(id)
    }

    @Test("R46: the POST carries the oracle's fields with raison filled, in document order, to the oracle's URL")
    func differential() async throws {
        let outcome = await ModeratorAlertHarness.run(
            page: try ModeratorAlertHarness.formPage(), reason: "Alert reason", answer: try Self.answer("W20a")
        )
        let legacy = try ModeratorAlertPrepareTests.legacyOracle()
        let post = try #require(legacy["post"] as? [String: Any])
        let legacyPairs = try #require(post["pairs"] as? [[String]])
        // Legacy sent its dictionary's order; a browser sends the controls in document order.
        let documentOrder = [
            ["hash_check", "REDACTED"], ["referer_page", ""], ["raison", "Alert reason"], ["Submit", "Valider votre message"]
        ]
        #expect(outcome.pairs == documentOrder)
        #expect(outcome.pairs.sorted { $0[0] < $1[0] } == legacyPairs.sorted { $0[0] < $1[0] })
        #expect(outcome.post?.url.absoluteString == post["url"] as? String)
        #expect(outcome.post?.headers["Content-Type"] == FormBody.contentType)
        #expect(outcome.post?.redirectPolicy == .doNotFollow)
        #expect(outcome.post?.timeout == PostingFlow.postTimeout)
        #expect(outcome.requests.map(\.method) == [.get, .post])
    }

    @Test("Line breaks are sent as CRLF, as a browser and legacy did")
    func crlf() async throws {
        let outcome = await ModeratorAlertHarness.run(
            page: try ModeratorAlertHarness.formPage(), reason: "ligne 1\nligne 2\r\nfin", answer: try Self.answer("W20a")
        )
        #expect(outcome.pairs.first { $0.first == "raison" } == ["raison", "ligne 1\r\nligne 2\r\nfin"])
    }

    @Test("A blank reason or characters outside the BMP are refused before sending", arguments: [
        ("  \n\t", ModeratorAlertError.emptyReason),
        ("Spam 😀 encore 😀 🚫", .unsupportedCharacters(["😀", "🚫"]))
    ])
    func refusedReason(reason: String, expected: ModeratorAlertError) async throws {
        let outcome = await ModeratorAlertHarness.run(page: try ModeratorAlertHarness.formPage(), reason: reason)
        #expect(outcome.error == expected)
        #expect(outcome.post == nil)
    }

    private static func served(_ file: String) throws -> Result<HTTPResponse, NetworkError> {
        .success(try Capture.response(file, url: ModeratorAlertHarness.link))
    }

    @Test("W46, HFR's confirmation of a submitted alert, is the success, with HFR's sentence, one POST")
    func capturedAnswer() async throws {
        let outcome = await ModeratorAlertHarness.run(
            page: try ModeratorAlertHarness.formPage(), reason: "Spam", answer: try Self.served("W46-modo-alert-success")
        )
        #expect(outcome.answer == .success(ModeratorAlertAnswer(message: "Un message a été envoyé avec succès aux modérateurs")))
        #expect(outcome.requests.map(\.method) == [.get, .post])
    }

    @Test("The other captured refusals are rejected with HFR's own sentence, one POST", arguments: [
        "W20a", "W17a", "W17b", "R88-modo-alert-already-reported", "W43-poll-vote-already-voted"
    ])
    func rejectedAnswers(id: String) async throws {
        let isCapture = id.contains("-")
        let answer = isCapture ? try Self.served(id) : try Self.answer(id)
        let outcome = await ModeratorAlertHarness.run(page: try ModeratorAlertHarness.formPage(), reason: "Spam", answer: answer)
        let html = try Capture.page(isCapture ? id : PostingCapture.answers[id] ?? id)
        let expected = try #require(try HopResponseParser.classify(html: html).message)
        #expect(outcome.error == .rejected(message: expected))
        #expect(outcome.requests.filter { $0.method == .post }.count == 1)
    }

    @Test("Another write's confirmation (W10, W42) is not an alert's: unconfirmed, with HFR's sentence", arguments: [
        "W10", "W42-poll-vote-success"
    ])
    func otherConfirmations(id: String) async throws {
        let isCapture = id.contains("-")
        let answer = isCapture ? try Self.served(id) : try Self.answer(id)
        let outcome = await ModeratorAlertHarness.run(page: try ModeratorAlertHarness.formPage(), reason: "Spam", answer: answer)
        let html = try Capture.page(isCapture ? id : PostingCapture.answers[id] ?? id)
        let expected = try #require(try HopResponseParser.classify(html: html).message)
        #expect(outcome.error == .unconfirmed(.unrecognizedAnswer(message: expected)))
    }

    @Test("W46's body served as a redirect is not HFR's answer: unconfirmed")
    func redirectedConfirmation() async throws {
        let body = try Capture.response("W46-modo-alert-success", url: ModeratorAlertHarness.link).body
        let redirect = HTTPResponse(
            statusCode: 302,
            headers: ["Content-Type": "text/html; charset=utf-8", "Location": "/user/modo.php"],
            url: ModeratorAlertHarness.link,
            body: body
        )
        let outcome = await ModeratorAlertHarness.run(
            page: try ModeratorAlertHarness.formPage(), reason: "Spam", answer: .success(redirect)
        )
        #expect(outcome.error == .unconfirmed(.unrecognizedAnswer(message: nil)))
    }

    @Test("HFR's logged-out sentences after the POST (W47 for an alert, W17c) are notLoggedIn", arguments: [
        "W47-modo-alert-logged-out-rejected", "W17c"
    ])
    func loggedOutAnswer(id: String) async throws {
        let answer = id.contains("-") ? try Self.served(id) : try Self.answer(id)
        let outcome = await ModeratorAlertHarness.run(page: try ModeratorAlertHarness.formPage(), reason: "Spam", answer: answer)
        #expect(outcome.error == .notLoggedIn)
    }

    @Test("An answer without a sentence, or a failed exchange, is unconfirmed and never retried", arguments: [
        "page", "empty", "timeout"
    ])
    func unconfirmed(answer kind: String) async throws {
        let reply: Result<HTTPResponse, NetworkError> = switch kind {
        case "page": .success(try Capture.response("R20-topic-p1-anon", url: ModeratorAlertHarness.link))
        case "empty": ModeratorAlertHarness.fragment("")
        default: .failure(.timedOut)
        }
        let outcome = await ModeratorAlertHarness.run(page: try ModeratorAlertHarness.formPage(), reason: "Spam", answer: reply)
        let expected: ModeratorAlertError = kind == "timeout"
            ? .unconfirmed(.transport(.timedOut)) : .unconfirmed(.unrecognizedAnswer(message: nil))
        #expect(outcome.error == expected)
        #expect(outcome.requests.map(\.method) == [.get, .post])
    }

    @Test("A request the session refuses to send is a plain network failure: nothing left")
    func refusedBySession() async throws {
        let outcome = await ModeratorAlertHarness.run(
            page: try ModeratorAlertHarness.formPage(), reason: "Spam", answer: .failure(.invalidRequest(reason: "host"))
        )
        #expect(outcome.error == .network(.invalidRequest(reason: "host")))
    }

    // MARK: - Session changes (#342)

    /// A fake token, read with the new cookies.
    private static let fresher = "fresher-token-0456"

    @Test(
        "A login of another account or a logout after the alert page was read refuses the submit, nothing sent",
        arguments: [ConcurrentLogin(identity: "user2", hashCheck: fresher), ConcurrentLogin(identity: nil, hashCheck: "")]
    )
    func changeAfterPrepare(change: ConcurrentLogin) async throws {
        let outcome = await ModeratorAlertHarness.run(
            page: try ModeratorAlertHarness.formPage(), reason: "Spam", answer: try Self.answer("W20a"), between: change
        )
        #expect(outcome.error == .sessionChanged)
        #expect(outcome.requests.map(\.method) == [.get])
    }

    @Test("A login of another account while the alert page is in flight refuses the submit, nothing sent")
    func switchDuringPrepare() async throws {
        let outcome = await ModeratorAlertHarness.run(
            page: try ModeratorAlertHarness.formPage(), reason: "Spam", answer: try Self.answer("W20a"),
            duringPrepare: ConcurrentLogin(identity: "user2", hashCheck: Self.fresher)
        )
        #expect(outcome.error == .sessionChanged)
        #expect(outcome.requests.map(\.method) == [.get])
    }

    @Test("A re-login of the same account, during or after the prepare, still sends the alert", arguments: [true, false])
    func sameAccountRelogin(duringPrepare: Bool) async throws {
        let relogin = ConcurrentLogin(identity: "user1", hashCheck: Self.fresher)
        let outcome = await ModeratorAlertHarness.run(
            page: try ModeratorAlertHarness.formPage(), reason: "Spam", answer: try Self.served("W46-modo-alert-success"),
            duringPrepare: duringPrepare ? relogin : nil, between: duringPrepare ? nil : relogin
        )
        #expect(outcome.error == nil)
        #expect(outcome.requests.map(\.method) == [.get, .post])
    }

    @Test(
        "A cancellation during the identity lookup sends nothing and is a plain cancellation, even after a switch",
        arguments: [false, true]
    )
    func cancelledDuringIdentityLookup(switched: Bool) async throws {
        let session = ScriptedPostingSession([try ModeratorAlertHarness.formPage(), try Self.answer("W20a")])
        let flow = ModeratorAlertFlow()
        let page = try await flow.prepare(link: ModeratorAlertHarness.link, through: session)
        guard case let .form(form) = page else {
            Issue.record("expected the form, got \(page)")
            return
        }
        if switched { await session.adoptLogin(ConcurrentLogin(identity: "user2", hashCheck: Self.fresher)) }
        await session.cancelCallerOnIdentityRead()
        let result = await Task { () async -> Result<ModeratorAlertAnswer, ModeratorAlertError> in
            do throws(ModeratorAlertError) {
                return .success(try await flow.submit(reason: "Spam", with: form))
            } catch {
                return .failure(error)
            }
        }.value
        #expect(result == .failure(.network(.cancelled)))
        #expect(await session.requests.map(\.method) == [.get])
    }
}
