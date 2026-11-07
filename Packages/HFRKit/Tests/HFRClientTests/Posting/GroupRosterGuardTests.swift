import Foundation
import HFRModels
import HFRNetwork
import Testing
@testable import HFRClient

/// LOT-058: what a group roster change refuses before its POST, and the session gate. Every run is scripted (#507 captures);
/// these assert that no POST was even attempted.
@Suite("Group roster changes: guards")
struct GroupRosterGuardTests {
    // MARK: - Refused before sending

    @Test("A change that would leave fewer than two others is refused: W72 left a form without newdest (R124)", arguments: [
        ("R123c", ["user3"]), ("R127", ["user3"]), ("R127", ["user3", "USER3"]), ("R127", ["user3", " user3 "])
    ])
    func tooFewMembers(id: String, members: [String]) async throws {
        let run = try await GroupRosterHarness.run(form: id, members: members)
        #expect(run.error == .tooFewMembers(minimum: 2))
        GroupRosterHarness.sentNothing(run)
        #expect(run.checks == 0)
    }

    @Test("An empty roster is refused: HFR takes it as \"no change\" (W77), never as \"remove everyone\"", arguments: [
        [String](), [""], ["  ", "\n"]
    ])
    func emptyRoster(members: [String]) async throws {
        let run = try await GroupRosterHarness.run(form: "R127", members: members)
        #expect(run.error == .emptyRoster)
        GroupRosterHarness.sentNothing(run)
        #expect(run.checks == 0)
    }

    @Test("A form without newdest is refused: a member, one-to-one, a two-person thread, a public topic", arguments: [
        "R123e", "R138", "R47b", "R47u1", "R124", "R61b", "R43a", "R45b"
    ])
    func rosterNotOffered(id: String) async throws {
        let run = try await GroupRosterHarness.run(form: id, members: ["user3", "user4"])
        #expect(run.error == .rosterNotOffered)
        GroupRosterHarness.sentNothing(run)
        #expect(run.checks == 0)
    }

    @Test("A newdest served empty offers no change (R127 edited, no capture shows it)")
    func servedEmpty() async throws {
        let page = try PostingHarness.editedForm("R127") { $0.replacing(#"value="user3, user4, user2""#, with: #"value="""#) }
        let session = ScriptedPostingSession([page])
        let form = try await PostingFlow().loadForm(at: try PostingCapture.pageURL("R127"), through: session)
        let run = await GroupRosterHarness.run(form, session, members: ["user3", "user4"])
        #expect(run.error == .rosterNotOffered)
        GroupRosterHarness.sentNothing(run)
    }

    @Test("A name that is not one member for HFR is refused before it is counted", arguments: [
        ["user3, user4"], ["user3", "user3,"], ["user3", "us\ner4"], ["user3", "user😀4"]
    ])
    func invalidNames(members: [String]) async throws {
        let run = try await GroupRosterHarness.run(form: "R127", members: members)
        #expect(run.error == .invalidMemberName)
        GroupRosterHarness.sentNothing(run)
    }

    @Test("The owner cannot be listed: it would count as a member kept, and HFR's answer is not captured", arguments: [
        ["user1", "user3"], ["user3", "user4", "USER1"]
    ])
    func namesOwner(members: [String]) async throws {
        let run = try await GroupRosterHarness.run(form: "R127", members: members)
        #expect(run.error == .namesOwner)
        GroupRosterHarness.sentNothing(run)
    }

    @Test("The text is the reply's: refused as any reply's, before the session check")
    func refusedText() async throws {
        let run = try await GroupRosterHarness.run(form: "R127", members: ["user3", "user4"], text: "  ")
        #expect(run.error == .posting(.emptyInput(.text)))
        GroupRosterHarness.sentNothing(run)
        #expect(run.checks == 0)
    }

    // MARK: - Session gate

    @Test("A session the check does not confirm sends nothing; a check that fails is a network failure", arguments: [
        Result<SessionHealth, NetworkError>.success(.expired(.noIdentityCookie)),
        .success(.unconfirmed(.unrecognizedPage)), .failure(.timedOut), .failure(.offline)
    ])
    func unconfirmedSession(check: Result<SessionHealth, NetworkError>) async throws {
        let run = try await GroupRosterHarness.run(form: "R127", members: ["user3", "user4"], check: check)
        switch check {
        case .success(let health): #expect(run.error == .sessionNotConfirmed(health))
        case .failure(let failure): #expect(run.error == .posting(.network(failure)))
        }
        GroupRosterHarness.sentNothing(run)
        #expect(run.checks == 1)
    }

    @Test("A login of another account after the form was loaded sends nothing")
    func sessionChanged() async throws {
        let session = ScriptedPostingSession([try PostingCapture.form("R127")])
        let form = try await PostingFlow().loadForm(at: try PostingCapture.pageURL("R127"), through: session)
        await session.adoptLogin(ConcurrentLogin(identity: "user2", hashCheck: "fake-token-other"))
        let run = await GroupRosterHarness.run(form, session, members: ["user3", "user4"])
        #expect(run.error == .posting(.sessionChanged))
        GroupRosterHarness.sentNothing(run)
    }

    @Test("A cancelled task asks nothing and sends nothing")
    func cancelled() async throws {
        let session = ScriptedPostingSession([try PostingCapture.form("R127")])
        let form = try await PostingFlow().loadForm(at: try PostingCapture.pageURL("R127"), through: session)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await GroupRosterHarness.run(form, session, members: ["user3", "user4"])
        }
        let run = await task.value
        #expect(run.error == .posting(.network(.cancelled)))
        GroupRosterHarness.sentNothing(run)
        #expect(run.checks == 0)
    }
}
