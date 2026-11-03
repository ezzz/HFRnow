import Foundation
import HFRModels
@testable import HFRNetwork
import Testing
@testable import HFRClient

/// LOT-094: the MP thread delete, its request checked against `W64`'s and the MP list form (`R95k`), its answers against
/// the captures `W64`, `W65` (success), `W64x` (bad token) and other writes' pages. Writes go to scripted sessions or to
/// a session that may only contact the loopback host; cookie values and tokens are fake.
@Suite("MP thread delete (LOT-094)")
struct DeletePrivateMessageFlowTests {
    /// The thread `W64` deleted.
    static let thread = TopicID(category: .privateMessages, topic: 3_207_675)
    static let token = "fake-token-0123"

    // MARK: - Request

    @Test("The delete POSTs W64's body, byte for byte and in its order, to W64's URL, once, without following redirects")
    func requestIsW64s() async throws {
        let meta = try Capture.meta("W64")
        let session = ScriptedFlagSession([try FlagCapture.page("W64")], hashCheck: "REDACTED")
        _ = try await DeletePrivateMessageFlow().send(Self.thread, through: session, since: await session.hashCheckSeed())
        let requests = await session.requests
        #expect(requests.count == 1)
        let post = try #require(requests.first)
        #expect(post.method == .post)
        #expect(post.redirectPolicy == .doNotFollow)
        #expect(post.url.absoluteString == meta.url)
        #expect(post.headers["Content-Type"] == FormBody.contentType)
        let body = post.body.flatMap { String(bytes: $0, encoding: .utf8) }
        #expect(body == meta.requestBody)
        #expect(DeletePrivateMessageFlow.body(thread: 1, token: "t").fields.map(\.name) == meta.requestFields)
        #expect(try Capture.meta("W65").requestFields == meta.requestFields)
    }

    @Test("Every field but legacy's `type_page` and fixed end marker is a control of the MP list form, and so is the action")
    func bodyMatchesTheListForm() throws {
        let html = try Capture.page("R95k-mp-list-recipient-after-thread-delete")
        let start = try #require(html.firstRange(of: #"<form name="form1""#))
        let end = try #require(html[start.upperBound...].firstRange(of: "</form>"))
        let form = html[start.lowerBound..<end.lowerBound]
        let names = Set(form.matches(of: /name="([^"]+)"/).map { String($0.output.1) })
        let sent = DeletePrivateMessageFlow.body(thread: 1, token: "t").fields.map(\.name)
        // A 50-row list puts its end marker at index 50 (`topic_statusno50`); the site form has no `type_page`.
        #expect(Set(sent).subtracting(names) == ["type_page", "topic_statusno1"])
        #expect(form.contains(#"<option value="valid_eff_prive">"#))
        #expect(form.contains(#"name="valuecat0" value="prive""#))
        let action = DeletePrivateMessageFlow.manageActionURL.absoluteString.replacing("https://forum.hardware.fr", with: "")
        #expect(form.contains(#"action="\#(action.replacing("&", with: "&amp;"))""#))
    }

    @Test(
        "A thread that is not an MP thread is refused unsent",
        arguments: [
            TopicID(category: .forum(13), topic: 28563), TopicID(category: .privateMessages, topic: 0),
            TopicID(category: .privateMessages, topic: -3)
        ]
    )
    func invalidThread(thread: TopicID) async throws {
        let session = ScriptedFlagSession([try FlagCapture.page("W64")], hashCheck: Self.token)
        await #expect(throws: MPThreadDeleteError.invalidThread) {
            try await DeletePrivateMessageFlow().send(thread, through: session, since: await session.hashCheckSeed())
        }
        var checked = false
        await #expect(throws: MPThreadDeleteError.invalidThread) {
            try await DeletePrivateMessageFlow().delete(thread, through: session) { () async throws(NetworkError) in
                checked = true
                return .valid
            }
        }
        #expect(!checked)
        #expect(await session.requests.isEmpty)
    }

    // MARK: - Answers

    @Test("The owner's (W64) and the recipient's (W65) answers confirm the delete, with the MP list refresh", arguments: ["W64", "W65"])
    func capturedSuccess(id: String) async throws {
        let session = ScriptedFlagSession([try FlagCapture.page(id)], hashCheck: Self.token)
        let result = try await DeletePrivateMessageFlow().send(
            Self.thread, through: session, since: await session.hashCheckSeed()
        )
        #expect(result.thread == Self.thread)
        #expect(result.message == "Action effectuée avec succès")
        #expect(
            result.refreshURL.absoluteString == "https://forum.hardware.fr/forum1.php?config=hfr.inc&cat=prive&page=1&subcat="
                + "&sondage=0&owntopic=0&trash=0&trash_post=0&moderation=0&new=0&nojs=0&subcatgroup=0"
        )
    }

    @Test("The bad-token answer (W64x, nothing deleted) is a refusal with HFR's sentence")
    func badTokenIsRejected() async throws {
        let session = ScriptedFlagSession([try FlagCapture.page("W64x")], hashCheck: Self.token)
        let error = await Self.failure(Self.thread, session)
        guard case .rejected(let message)? = error else {
            Issue.record("expected a refusal, got \(String(describing: error))")
            return
        }
        #expect(message?.hasPrefix("Une erreur est survenue lors de l'envoi des données") == true)
    }

    @Test("A logged-out refusal (W17c's shape) is notLoggedIn")
    func loggedOutIsNotLoggedIn() async throws {
        let session = ScriptedFlagSession([try FlagCapture.page("W17c")], hashCheck: Self.token)
        #expect(await Self.failure(Self.thread, session) == .notLoggedIn)
    }

    @Test(
        "Another write's confirmation never confirms the delete",
        arguments: [
            ("W18", "Le message a été marqué comme non lu avec succès"), ("P03j", "Drapeaux effacés avec succès"),
            ("P03d", "Drapeau effacé avec succès"), ("W15", "Votre message a été édité avec succès !")
        ]
    )
    func otherConfirmations(id: String, sentence: String) async throws {
        let session = ScriptedFlagSession([try FlagCapture.page(id)], hashCheck: Self.token)
        let error = await Self.failure(Self.thread, session)
        guard case .unconfirmed(.unexpectedConfirmation(let message))? = error else {
            Issue.record("expected an unexpected confirmation, got \(String(describing: error))")
            return
        }
        #expect(message == sentence)
    }

    @Test(
        "W64's sentence with a refresh to another page than the MP list is not the delete's confirmation",
        arguments: [
            "/forum1.php?config=hfr.inc&amp;cat=13&amp;page=1", "/forum1f.php?config=hfr.inc&amp;cat=prive&amp;page=1",
            "/forum1.php?config=hfr.inc&amp;cat=prive&amp;cat=13&amp;page=1", "/"
        ]
    )
    func otherRefreshIsUnexpected(target: String) async throws {
        let html = try Capture.page("W64-mp-thread-delete-owner-success")
        let original = try #require(html.firstMatch(of: /url=([^"]*)"/)).output.1
        let page = html.replacing(String(original), with: target)
        #expect(page != html)
        let response = HTTPResponse(
            statusCode: 200, headers: ["Content-Type": "text/html; charset=utf-8"],
            url: DeletePrivateMessageFlow.manageActionURL, body: Data(page.utf8)
        )
        let session = ScriptedFlagSession([.success(response)], hashCheck: Self.token)
        let expected = MPThreadDeleteError.unconfirmed(.unexpectedConfirmation(message: "Action effectuée avec succès"))
        #expect(await Self.failure(Self.thread, session) == expected)
    }

    @Test("A page that is neither a confirmation nor a refusal (the MP list R95j) is unconfirmed, never a success")
    func otherPageIsUnconfirmed() async throws {
        let session = ScriptedFlagSession([try FlagCapture.page("R95j")], hashCheck: Self.token)
        guard case .unconfirmed(.unrecognizedAnswer)? = await Self.failure(Self.thread, session) else {
            Issue.record("expected an unrecognized answer")
            return
        }
    }

    @Test("A redirect, even with W64's body, is unconfirmed")
    func redirectIsUnconfirmed() async throws {
        let response = HTTPResponse(
            statusCode: 302, headers: ["Location": "/forum1.php?config=hfr.inc&cat=prive"],
            url: DeletePrivateMessageFlow.manageActionURL,
            body: Data(try Capture.page("W64-mp-thread-delete-owner-success").utf8)
        )
        let session = ScriptedFlagSession([.success(response)], hashCheck: Self.token)
        #expect(await Self.failure(Self.thread, session) == .unconfirmed(.unrecognizedAnswer(message: nil)))
    }

    @Test(
        "A failure after sending is unconfirmed; a request refused before leaving is a network failure",
        arguments: [
            (NetworkError.timedOut, MPThreadDeleteError.unconfirmed(.transport(.timedOut))),
            (.httpStatus(code: 500, url: DeletePrivateMessageFlow.manageActionURL),
             .unconfirmed(.transport(.httpStatus(code: 500, url: DeletePrivateMessageFlow.manageActionURL)))),
            (.invalidRequest(reason: "host"), .network(.invalidRequest(reason: "host")))
        ]
    )
    func transportFailures(failure: NetworkError, expected: MPThreadDeleteError) async throws {
        let session = ScriptedFlagSession([.failure(failure)], hashCheck: Self.token)
        #expect(await Self.failure(Self.thread, session) == expected)
        #expect(await session.requests.count == 1)
    }

    // MARK: - Helpers

    /// The error the fenced send throws with the session's own seed (no login change), nil when it succeeds.
    private static func failure(_ thread: TopicID, _ session: ScriptedFlagSession) async -> MPThreadDeleteError? {
        do throws(MPThreadDeleteError) {
            _ = try await DeletePrivateMessageFlow().send(thread, through: session, since: await session.hashCheckSeed())
            return nil
        } catch {
            return error
        }
    }
}
