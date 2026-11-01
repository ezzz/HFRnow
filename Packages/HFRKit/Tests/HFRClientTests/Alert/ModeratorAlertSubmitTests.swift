import Foundation
import HFRModels
import HFRNetwork
import HFRParsing
import Testing
@testable import HFRClient

/// LOT-050 `submit`: `R46`'s form posted like a browser (the LOT-004 oracle's fields, `raison` filled), once, never
/// retried; HFR's answer to `modo.php` is not captured (#136), so captured write answers stand in for its shapes and
/// none of them is reported as a success.
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

    @Test(
        "Every answer with a sentence is returned as HFR's own text, never a success or a refusal (#136 pending)",
        arguments: ["W10", "W20a", "W17a", "W17b"]
    )
    func answers(id: String) async throws {
        let outcome = await ModeratorAlertHarness.run(
            page: try ModeratorAlertHarness.formPage(), reason: "Spam", answer: try Self.answer(id)
        )
        let html = try Capture.page(PostingCapture.answers[id] ?? id)
        let expected = try #require(try HopResponseParser.classify(html: html).message)
        #expect(outcome.answer == .success(ModeratorAlertAnswer(message: expected)))
        #expect(outcome.requests.filter { $0.method == .post }.count == 1)
    }

    @Test("HFR's logged-out sentence after the POST (W17c) is notLoggedIn")
    func loggedOutAnswer() async throws {
        let outcome = await ModeratorAlertHarness.run(
            page: try ModeratorAlertHarness.formPage(), reason: "Spam", answer: try Self.answer("W17c")
        )
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
}
