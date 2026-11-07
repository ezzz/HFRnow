import Foundation
import HFRModels
import HFRNetwork
import Testing
@testable import HFRClient

/// LOT-058, group roster changes (#507 captures): the owner's reply with `newdest` edited. Every run is scripted: the form,
/// the POST's answer and the reload are captures, so no write can reach HFR.
@Suite("Group roster changes")
struct GroupRosterTests {
    // MARK: - The change

    @Test("W74: a member left out of newdest; the body is the captured one, the roster is the reloaded composer's")
    func removeMember() async throws {
        let run = try await GroupRosterHarness.run(
            form: "R127", members: ["user3", "user4"], replies: [try PostingCapture.answer("W74"), try PostingCapture.form("R128")]
        )
        let change = try run.result.get()
        #expect(change.posting.action == .reply)
        #expect(change.posting.message == "Votre réponse a été postée avec succès !")
        // R128's aliases are not W74's: this list can only come from the page, not from what was sent.
        #expect(change.members == ["user4", "user5"])
        let boxes: Set = ["signature", "smiley", "emaill"]
        let body = run.posts.first?.body.flatMap { String(bytes: $0, encoding: .utf8) }
        #expect(body == (try PostingHarness.browserBody(of: "W74", checkboxes: boxes)))
        #expect(run.requests.map(\.method) == [.get, .post, .get])
        #expect(run.requests.last?.url == (try PostingCapture.pageURL("R127")))
        #expect(run.checks == 1)
    }

    @Test("W75: a member appended to newdest, at its place between pseudo and password, once")
    func addMember() async throws {
        let run = try await GroupRosterHarness.run(
            form: "R128", members: ["user3", "user4", "user2"],
            replies: [try PostingCapture.answer("W75"), try PostingCapture.form("R132")]
        )
        #expect(try run.result.get().members == ["user4", "user5", "user2"])
        #expect(run.newdest == ["user3, user4, user2"])
        #expect(run.newdest.first == PostingHarness.pairs(of: try #require(try Capture.meta("W75").requestBody))
            .first { $0.name == "newdest" }?.value)
        let body = try #require(run.posts.first?.body.flatMap { String(bytes: $0, encoding: .utf8) })
        let names = PostingHarness.pairs(of: body).map(\.name)
        let roster = try #require(names.firstIndex(of: "newdest"))
        #expect(names[roster - 1] == "pseudo")
        #expect(names[roster + 1] == "password")
    }

    @Test("Names are trimmed, blanks and repeats dropped (case-insensitive, the first spelling kept), the order is the caller's")
    func normalizedRoster() async throws {
        let run = try await GroupRosterHarness.run(
            form: "R127", members: [" user4 ", "", "user3", "USER4", "\tuser2\n"],
            replies: [try PostingCapture.answer("W74"), try PostingCapture.form("R128")]
        )
        #expect(run.newdest == ["user4, user3, user2"])
    }

    @Test("Reply options travel with the change")
    func options() async throws {
        let session = ScriptedPostingSession([try PostingCapture.form("R127"), try PostingCapture.answer("W74")])
        let form = try await PostingFlow().loadForm(at: try PostingCapture.pageURL("R127"), through: session)
        let change = try await GroupRosterFlow().changeMembers(
            to: ["user3", "user4"], text: GroupRosterHarness.text, options: [.signature: false], with: form
        ) { () async throws(NetworkError) -> SessionHealth in .valid }
        #expect(change.members == nil)
        let post = try #require(await session.requests.first { $0.method == .post })
        let body = try #require(post.body.flatMap { String(bytes: $0, encoding: .utf8) })
        #expect(PostingHarness.pairs(of: body).allSatisfy { $0.name != "signature" })
    }

    // MARK: - HFR's answers

    @Test("W76: an unknown pseudo is a refusal, with HFR's sentence as its text; nothing is reloaded")
    func unknownPseudo() async throws {
        let members = ["user3", "user4", "user2", "user5"]
        let run = try await GroupRosterHarness.run(form: "R127", members: members, replies: [try PostingCapture.answer("W76")])
        #expect(run.error == .posting(.rejected(message: "Désolé, le pseudo suivant n'existe pas : zqzhbhvwyigjqt")))
        #expect(run.posts.count == 1)
        #expect(run.requests.count == 2)
        #expect(run.newdest == ["user3, user4, user2, user5"])
    }

    @Test("A POST whose exchange fails is unconfirmed, sent once, never retried nor followed by a reload")
    func transportFailure() async throws {
        let run = try await GroupRosterHarness.run(form: "R127", members: ["user3", "user4"], replies: [.failure(.timedOut)])
        #expect(run.error == .posting(.unconfirmed(.transport(.timedOut))))
        #expect(run.posts.count == 1)
        #expect(run.requests.count == 2)
    }

    @Test("Another write's confirmation is unconfirmed; a logged-out page and a bad token are refusals")
    func otherAnswers() async throws {
        let members = ["user3", "user4"]
        let edit = try await GroupRosterHarness.run(form: "R127", members: members, replies: [try PostingCapture.answer("W15")])
        #expect(edit.error == .posting(.unconfirmed(.unexpectedConfirmation(message: "Votre message a été édité avec succès !"))))
        let loggedOut = try await GroupRosterHarness.run(form: "R127", members: members, replies: [try PostingCapture.answer("W17c")])
        #expect(loggedOut.error == .posting(.notLoggedIn))
        let badToken = try await GroupRosterHarness.run(form: "R127", members: members, replies: [try PostingCapture.answer("W17b")])
        guard case .posting(.rejected)? = badToken.error else {
            Issue.record("expected a refusal, got \(String(describing: badToken.error))")
            return
        }
    }

    @Test("The change stands when the reload fails or the composer serves no roster: the members are unknown, not an error")
    func reloadWithoutRoster() async throws {
        let answer = try PostingCapture.answer("W74")
        for reload in [GroupRosterHarness.Reply.failure(.timedOut), try PostingCapture.form("R124")] {
            let run = try await GroupRosterHarness.run(form: "R127", members: ["user3", "user4"], replies: [answer, reload])
            #expect(try run.result.get().members == nil)
            #expect(run.posts.count == 1)
        }
    }
}
