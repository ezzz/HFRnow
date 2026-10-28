import Foundation
import HFRModels
import HFRNetwork
import Testing
@testable import HFRClient

/// The favourites-list removal (`manageaction.php`) and the read mark (an authenticated topic page GET).
@Suite("Favourites list removal and read mark")
struct FavoriteListAndReadTests {
    static let cuisine = TopicID(category: .forum(13), topic: 28563)
    static let token = "fake-token-0123"

    // MARK: - List removal

    @Test("The removal POSTs legacy's body, in legacy's order, to the list's form action, once")
    func removalRequest() async throws {
        let session = ScriptedFlagSession([try FlagCapture.page("W20a")], hashCheck: Self.token)
        _ = try? await TopicFlagFlow().removeFavoriteFromList(Self.cuisine, through: session)
        let requests = await session.requests
        #expect(requests.count == 1)
        let post = try #require(requests.first)
        #expect(post.method == .post)
        #expect(post.redirectPolicy == .doNotFollow)
        #expect(
            post.url.absoluteString
                == "https://forum.hardware.fr/modo/manageaction.php?config=hfr.inc&cat=0&type_page=forum1f&moderation=0"
        )
        let body = post.body.flatMap { String(bytes: $0, encoding: .utf8) }
        #expect(
            body == "hash_check=fake-token-0123&topic1=-1&topic_statusno1=-1&action_reaction=message_forum_delflags"
                + "&type_page=forum1f&topic0=28563&valuecat0=13&valueforum0=hardwarefr"
        )
    }

    @Test(
        "Every field of the body is a control of the favourites form, and the action is its own",
        arguments: [
            // One row (P03c): the end marker is at index 1, as legacy writes it.
            ("P03c-favourites-after-addflag", [String]()),
            // Two rows (R10): the form puts the end marker at index 2; legacy's fixed `topic1` stands for the row 1 box.
            ("R10-favourites-owntopic1", ["topic_statusno1"])
        ]
    )
    func bodyMatchesTheListForm(file: String, notInForm: [String]) throws {
        do {
            let html = try Capture.page(file)
            let start = try #require(html.firstRange(of: #"<form name="form1""#))
            let end = try #require(html[start.upperBound...].firstRange(of: "</form>"))
            let form = html[start.lowerBound..<end.lowerBound]
            let names = Set(form.matches(of: /name="([^"]+)"/).map { String($0.output.1) })
            let sent = TopicFlagFlow.removalBody(topic: 1, category: 1, token: "t").fields.map(\.name)
            #expect(Set(sent).subtracting(names) == Set(notInForm), "\(file)")
            #expect(form.contains(#"<option value="message_forum_delflags">"#))
            let action = TopicFlagFlow.manageActionURL.absoluteString.replacing("https://forum.hardware.fr", with: "")
            #expect(form.contains(#"action="\#(action.replacing("&", with: "&amp;"))""#), "\(file)")
        }
    }

    @Test("Without a token nothing is sent")
    func missingToken() async throws {
        let session = ScriptedFlagSession([try FlagCapture.page("P03d")])
        await #expect(throws: TopicFlagError.missingToken) {
            try await TopicFlagFlow().removeFavoriteFromList(Self.cuisine, through: session)
        }
        #expect(await session.requests.isEmpty)
    }

    @Test(
        "A topic that is not a forum topic is refused unsent",
        arguments: [
            TopicID(category: .privateMessages, topic: 5), TopicID(category: .forum(0), topic: 5),
            TopicID(category: .forum(13), topic: 0), TopicID(category: .forum(13), topic: -3)
        ]
    )
    func invalidTopic(topic: TopicID) async throws {
        let session = ScriptedFlagSession([try FlagCapture.page("P03d")], hashCheck: Self.token)
        await #expect(throws: TopicFlagError.invalidTopic) {
            try await TopicFlagFlow().removeFavoriteFromList(topic, through: session)
        }
        await #expect(throws: TopicFlagError.invalidTopic) {
            try await TopicFlagFlow().markRead(topic, page: 1, through: session)
        }
        #expect(await session.requests.isEmpty)
    }

    @Test("Until its answer is captured, an \"avec succès\" page is not reported as the removal's success")
    func successShapeIsNotCaptured() async throws {
        // P03d is a delflag answer, served here only to exercise the rule: no manageaction answer is captured.
        let session = ScriptedFlagSession([try FlagCapture.page("P03d")], hashCheck: Self.token)
        await #expect(throws: TopicFlagError.unconfirmed(.confirmationNotCaptured(message: "Drapeau effacé avec succès"))) {
            try await TopicFlagFlow().removeFavoriteFromList(Self.cuisine, through: session)
        }
    }

    @Test("Refusals, logged out and transport failures of the removal")
    func removalFailures() async throws {
        let cases: [(Result<HTTPResponse, NetworkError>, (TopicFlagError) -> Bool)] = [
            (try FlagCapture.page("W17c"), { $0 == .notLoggedIn }),
            (try FlagCapture.page("W20a"), { if case .rejected(let message?) = $0 { message.contains("flood") } else { false } }),
            (try FlagCapture.page("W01"), { if case .unconfirmed(.unrecognizedAnswer) = $0 { true } else { false } }),
            (.failure(.timedOut), { $0 == .unconfirmed(.transport(.timedOut)) }),
            (.failure(.invalidRequest(reason: "r")), { $0 == .network(.invalidRequest(reason: "r")) })
        ]
        for (reply, matches) in cases {
            let session = ScriptedFlagSession([reply], hashCheck: Self.token)
            do {
                let result = try await TopicFlagFlow().removeFavoriteFromList(Self.cuisine, through: session)
                Issue.record("Unexpected success \(result)")
            } catch {
                #expect(matches(error), "\(error)")
            }
            #expect(await session.requests.count == 1)
        }
    }

    // MARK: - Read mark

    @Test("Reading page 1 with the session (R21) marks it read and records the page's token")
    func markReadConfirmed() async throws {
        let session = ScriptedFlagSession([try FlagCapture.page("R21")])
        let mark = try await TopicFlagFlow().markRead(Self.cuisine, page: 1, through: session)
        #expect(mark.topic == Self.cuisine)
        #expect(mark.page == 1)
        #expect(mark.pageCount >= 1)
        #expect(mark.pageURL == (try FlagCapture.finalURL("R21")))
        let requests = await session.requests
        #expect(requests.map(\.url) == [try FlagCapture.requestURL("R21")])
        #expect(requests.first?.method == .get)
        #expect(requests.first?.redirectPolicy == .follow)
        #expect(await session.hashChecks == ["REDACTED"])
    }

    @Test(
        "An anonymous page, another topic or an off-forum page is not a read mark",
        arguments: [
            ("R20", 28563, "https://forum.hardware.fr/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_1.htm"),
            ("R21", 99, "https://forum.hardware.fr/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_1.htm"),
            ("R21", 28563, "https://other.hardware.fr/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_1.htm"),
            ("R12", 28563, "https://forum.hardware.fr/forum1f.php?owntopic=1")
        ]
    )
    func markReadUnconfirmed(page: String, topic: Int, servedFrom: String) async throws {
        var response = try FlagCapture.response(page)
        response.url = try FlagCapture.url(servedFrom)
        let session = ScriptedFlagSession([.success(response)])
        do {
            let mark = try await TopicFlagFlow().markRead(TopicID(category: .forum(13), topic: topic), page: 1, through: session)
            Issue.record("Unexpected mark \(mark)")
        } catch {
            guard case .unconfirmed(.unrecognizedAnswer) = error else {
                Issue.record("\(error)")
                return
            }
        }
        #expect(await session.hashChecks.isEmpty)
    }

    @Test("A page below 1 is refused unsent; a failed read is unconfirmed")
    func markReadInputs() async throws {
        let session = ScriptedFlagSession([.failure(.offline)])
        await #expect(throws: TopicFlagError.invalidTopic) {
            try await TopicFlagFlow().markRead(Self.cuisine, page: 0, through: session)
        }
        #expect(await session.requests.isEmpty)
        await #expect(throws: TopicFlagError.unconfirmed(.transport(.offline))) {
            try await TopicFlagFlow().markRead(Self.cuisine, page: 3, through: session)
        }
        #expect(await session.requests.map(\.url.absoluteString) == [
            "https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=13&post=28563&page=3"
        ])
    }
}
