import Foundation
import HFRModels
@testable import HFRNetwork
import HFRParsing
import Testing
@testable import HFRClient

/// LOT-050 `prepare`: the alert link of `R21` loads `R46`, whose form equals its LOT-004 oracle; "already alerted" is
/// LOT-037's reading of captured `.hop` pages (the real page is pending capture #135); links and actions stay on the
/// alert page of the same forum message.
@Suite("Moderator alert: prepare")
struct ModeratorAlertPrepareTests {
    private static func form(_ outcome: ModeratorAlertHarness.Outcome) throws -> ModeratorAlertForm {
        guard case let .success(.form(form)) = outcome.page else { throw Capture.Missing(name: "form in \(outcome.page)") }
        return form
    }

    @Test("R21's alert link of message 2666649 is R46's request")
    func linkFromTopicPage() throws {
        let actions = try MessageActionsParser.actions(in: Capture.page("R21-topic-p1-logged-in"))
        let link = try #require(actions.compactMap(\.alertURL).first { HFRURL.numreponse(in: $0.absoluteString) == 2666649 })
        #expect(link == ModeratorAlertHarness.link)
        #expect(link.absoluteString == (try Capture.meta("R46").url))
        let target = try #require(ModeratorAlertTarget(link))
        #expect(target.topic == TopicID(category: .forum(13), topic: 28563))
        #expect(target.numreponse == 2666649)
    }

    @Test("R46: the prepared form equals the LOT-004 oracle (inputs, action), one GET, the token recorded")
    func differential() async throws {
        let outcome = await ModeratorAlertHarness.run(page: try ModeratorAlertHarness.formPage())
        let form = try Self.form(outcome)
        let legacy = try Self.legacyOracle()
        var inputs: [String: String] = [:]
        for field in form.form.fields { inputs[field.name] = field.value }
        #expect(inputs == legacy["inputData"] as? [String: String])
        #expect(form.submitURL.absoluteString == legacy["formSubmit"] as? String)
        #expect(form.target == ModeratorAlertTarget(ModeratorAlertHarness.link))
        #expect(outcome.requests.map(\.method) == [.get])
        #expect(outcome.requests.first?.url == ModeratorAlertHarness.link)
        #expect(outcome.hashChecks == ["REDACTED"])
    }

    @Test(
        "A captured .hop page with a link or an input is 'already alerted', with HFR's own sentence (#135 pending)",
        arguments: ["W17a-mp-reply-empty-body-rejected", "W20a-mp-reply-flood", "RA5-mp-thread-after-delete-owner"]
    )
    func alreadyAlerted(file: String) async throws {
        let page = Result<HTTPResponse, NetworkError>.success(try Capture.response(file, url: ModeratorAlertHarness.link))
        let outcome = await ModeratorAlertHarness.run(page: page)
        let expected = try HopResponseParser.classify(html: Capture.page(file), context: .alertPrepare).message
        guard case let .success(.alreadyAlerted(message)) = outcome.page else {
            Issue.record("\(file): \(outcome.page)")
            return
        }
        #expect(message != nil)
        #expect(message == expected)
        #expect(outcome.hashChecks.isEmpty)
    }

    @Test("HFR's logged-out sentence (W17c) is notLoggedIn, not 'already alerted'")
    func loggedOut() async throws {
        let page = Result<HTTPResponse, NetworkError>.success(
            try Capture.response("W17c-mp-reply-logged-out-rejected", url: ModeratorAlertHarness.link)
        )
        let outcome = await ModeratorAlertHarness.run(page: page)
        #expect(outcome.error == .notLoggedIn)
    }

    @Test("A page with neither the form nor a .hop (R20) is formUnavailable")
    func noForm() async throws {
        let page = Result<HTTPResponse, NetworkError>.success(try Capture.response("R20-topic-p1-anon", url: ModeratorAlertHarness.link))
        let outcome = await ModeratorAlertHarness.run(page: page)
        #expect(outcome.error == .formUnavailable(message: nil))
        #expect(outcome.hashChecks.isEmpty)
    }

    // MARK: - Form rules (small fragments: the structure the rules read)

    private static let action = "modo.php?cat=13&amp;ref=1&amp;post=28563&amp;numreponse=2666649&amp;page=1&amp;config=hfr.inc"

    private static func alertForm(action: String = action, token: String = "t0k3n", textarea: String = "raison") -> String {
        "<form method=\"post\" action=\"\(action)\"><input type=\"hidden\" name=\"hash_check\" value=\"\(token)\" />"
            + "<textarea name=\"\(textarea)\"></textarea><input type=\"submit\" name=\"Submit\" value=\"Valider votre message\" /></form>"
    }

    @Test("An empty token means a logged-out session; nothing is recorded")
    func emptyToken() async {
        let outcome = await ModeratorAlertHarness.run(page: ModeratorAlertHarness.fragment(Self.alertForm(token: "")))
        #expect(outcome.error == .notLoggedIn)
        #expect(outcome.hashChecks.isEmpty)
    }

    @Test("A form without the raison textarea is not the alert form")
    func noReasonField() async {
        let outcome = await ModeratorAlertHarness.run(page: ModeratorAlertHarness.fragment(Self.alertForm(textarea: "content_form")))
        #expect(outcome.error == .formUnavailable(message: nil))
    }

    @Test("The action must be the alert page of the same message, on the forum origin", arguments: [
        "modo.php?cat=13&amp;ref=1&amp;post=28563&amp;numreponse=2666650&amp;page=1&amp;config=hfr.inc",
        "modo.php?cat=13&amp;ref=1&amp;post=28564&amp;numreponse=2666649&amp;page=1&amp;config=hfr.inc",
        "https://example.org/user/modo.php?cat=13&amp;post=28563&amp;numreponse=2666649&amp;config=hfr.inc",
        "/user/modo.php.bak?cat=13&amp;post=28563&amp;numreponse=2666649&amp;config=hfr.inc",
        "/modo.php?cat=13&amp;post=28563&amp;numreponse=2666649&amp;config=hfr.inc",
        "/x/user/modo.php?cat=13&amp;post=28563&amp;numreponse=2666649&amp;config=hfr.inc"
    ])
    func otherAction(action: String) async {
        let outcome = await ModeratorAlertHarness.run(page: ModeratorAlertHarness.fragment(Self.alertForm(action: action)))
        #expect(outcome.error == .invalidLink)
        #expect(outcome.hashChecks.isEmpty)
    }

    // MARK: - Links

    @Test("Only the alert page of a forum message on https forum.hardware.fr is requested, at its exact path", arguments: [
        "http://forum.hardware.fr/user/modo.php?config=hfr.inc&cat=13&post=28563&numreponse=2666649",
        "https://example.org/user/modo.php?config=hfr.inc&cat=13&post=28563&numreponse=2666649",
        "https://forum.hardware.fr:8443/user/modo.php?config=hfr.inc&cat=13&post=28563&numreponse=2666649",
        "https://forum.hardware.fr/user/addflag.php?config=hfr.inc&cat=13&post=28563&numreponse=2666649",
        "https://forum.hardware.fr/user/modo.php?config=hfr.inc&cat=prive&post=3207033&numreponse=1980875029",
        "https://forum.hardware.fr/user/modo.php?config=hfr.inc&cat=13&post=28563&ref=0&page=1",
        "https://forum.hardware.fr/user/modo.php?config=hfr.inc&cat=13&cat=14&post=28563&numreponse=2666649",
        "https://forum.hardware.fr/user/modo.php?cat=13&post=28563&numreponse=2666649",
        "https://forum.hardware.fr/user/modo.php?config=hfr.inc&cat=0&post=28563&numreponse=2666649",
        "https://forum.hardware.fr/user/modo.php?config=hfr.inc&cat=13&post=0&numreponse=2666649",
        "https://forum.hardware.fr/user/modo.php?config=hfr.inc&cat=13&post=28563&numreponse=0",
        "https://forum.hardware.fr/modo.php?config=hfr.inc&cat=13&post=28563&numreponse=2666649",
        "https://forum.hardware.fr/x/user/modo.php?config=hfr.inc&cat=13&post=28563&numreponse=2666649"
    ])
    func refusedLinks(raw: String) async throws {
        let outcome = await ModeratorAlertHarness.run(link: try #require(URL(string: raw)), page: try ModeratorAlertHarness.formPage())
        #expect(outcome.error == .invalidLink)
        #expect(outcome.requests.isEmpty)
    }

    @Test(
        "A redirect that ends off the forum host is refused before reading the page, form or 'already alerted'",
        arguments: ["R46-modo-alert-form", "W20a-mp-reply-flood"]
    )
    func redirectedOffForum(file: String) async throws {
        let moved = PostingCapture.url("https://www.hardware.fr/user/modo.php?config=hfr.inc&cat=13&post=28563&numreponse=2666649")
        let page = Result<HTTPResponse, NetworkError>.success(try Capture.response(file, url: moved))
        let outcome = await ModeratorAlertHarness.run(page: page)
        #expect(outcome.error == .invalidLink)
        #expect(outcome.hashChecks.isEmpty)
    }

    @Test("The public entry point requests through the account's session: a loopback-only session sends nothing out")
    func publicEntryPoint() async {
        let session = HFRSession(
            cookies: [], hashCheck: "token", now: Date(), configuration: .ephemeral, hosts: .exactHost("127.0.0.1")
        )
        do throws(ModeratorAlertError) {
            _ = try await ModeratorAlertFlow().prepare(link: ModeratorAlertHarness.link, in: session)
            Issue.record("expected the request to be refused")
        } catch {
            guard case .network(.invalidRequest) = error else {
                Issue.record("expected the session to refuse the request, got \(error)")
                return
            }
        }
    }

    // MARK: - Oracle

    /// `result.legacy` of the LOT-004 oracle of `R46` (`AlerteModoViewController.m:153-180`, then `:197-240` on submit).
    static func legacyOracle() throws -> [String: Any] {
        let url = Capture.directory.deletingLastPathComponent().appendingPathComponent("LOT-004/R46.oracle.json")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        let result = (object as? [String: Any])?["result"] as? [String: Any]
        return try #require(result?["legacy"] as? [String: Any])
    }
}
