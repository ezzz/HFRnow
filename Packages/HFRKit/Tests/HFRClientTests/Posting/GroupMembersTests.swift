import Foundation
import HFRModels
import HFRNetwork
import HFRParsing
import Testing
@testable import HFRClient

/// LOT-058, group MP members (#336 captures): the roster the owner's reply composer serves in `newdest` (`R123c`), none on
/// a member's (`R123e`) or a one-to-one composer (`R47b`, `R47u1`), and a reply that sends it back as served.
@Suite("Group MP members")
struct GroupMembersTests {
    private static func form(_ id: String) async throws -> PostingForm {
        let session = ScriptedPostingSession([try PostingCapture.form(id)])
        return try await PostingFlow().loadForm(at: try PostingCapture.pageURL(id), through: session)
    }

    @Test("R123c: the owner's reply composer lists the other members, in the form's order")
    func ownerRoster() async throws {
        let form = try await Self.form("R123c")
        #expect(form.shape == .reply)
        #expect(form.isPrivateThread)
        #expect(form.groupMembers == ["user3", "user2"])
    }

    @Test("No roster on a member's composer nor on a one-to-one composer", arguments: ["R123e", "R47b", "R47u1"])
    func noRoster(id: String) async throws {
        let form = try await Self.form(id)
        #expect(form.shape == .reply)
        #expect(form.groupMembers == nil)
    }

    @Test("The owner's roster plus the owner is the roster of the same thread's MP list row (R123a)")
    func rosterMatchesList() async throws {
        let form = try await Self.form("R123c")
        let list = try PrivateMessageListParser.parse(
            try Capture.page("R123a-mp-list-group-owner"), pageURL: "/forum1.php?config=hfr.inc&cat=prive&page=1"
        )
        let thread = try #require(list.threads.first { $0.summary.topicID == TopicID(category: .privateMessages, topic: 3207958) })
        let owner = try #require(form.form.field(named: "pseudo")?.value)
        #expect(thread.interlocutors.first == owner)
        #expect(Set(thread.interlocutors) == Set(try #require(form.groupMembers) + [owner]))
    }

    @Test("A roster joined without spaces or with blanks splits on the comma alone (R123c edited)")
    func rosterSeparators() async throws {
        let page = try PostingHarness.editedForm("R123c") {
            $0.replacing(#"name="newdest" value="user3, user2""#, with: #"name="newdest" value=" user3,user2 , ,""#)
        }
        let form = try await PostingFlow().loadForm(
            at: try PostingCapture.pageURL("R123c"), through: ScriptedPostingSession([page])
        )
        #expect(form.groupMembers == ["user3", "user2"])
    }

    @Test("A newdest served empty is no roster: nil, like a form that serves none (R123c edited, no capture shows it)")
    func emptyRoster() async throws {
        let page = try PostingHarness.editedForm("R123c") {
            $0.replacing(#"name="newdest" value="user3, user2""#, with: #"name="newdest" value=" , ""#)
        }
        let form = try await PostingFlow().loadForm(
            at: try PostingCapture.pageURL("R123c"), through: ScriptedPostingSession([page])
        )
        #expect(form.form.field(named: "newdest") != nil)
        #expect(form.groupMembers == nil)
    }

    @Test("Every composer of the #507 run: the roster it serves, or none")
    func rosterEditComposers() async throws {
        for id in ["R127", "R128", "R132", "R136", "R137", "R139"] {
            #expect(try await Self.form(id).groupMembers?.count == (id == "R128" ? 2 : 3), "\(id)")
        }
        for id in ["R124", "R138"] {
            #expect(try await Self.form(id).groupMembers == nil, "\(id)")
        }
    }

    @Test("A reply from the owner's composer sends newdest unchanged, in the form's order (W71); a member's sends none")
    func replyKeepsRoster() async throws {
        let owner = try await PostingHarness.run(form: "R123c", answer: "W71") { flow, form async throws(PostingError) in
            try await flow.reply("group reply", with: form)
        }
        let pairs = PostingHarness.pairs(of: try #require(owner.body))
        #expect(pairs.filter { $0.name == "newdest" }.map(\.value) == ["user3, user2"])
        let names = pairs.map(\.name)
        let roster = try #require(names.firstIndex(of: "newdest"))
        // Document order (R123c): the roster row sits between the pseudo and the (hidden) password rows.
        #expect(names[roster - 1] == "pseudo")
        #expect(names[roster + 1] == "password")
        #expect(try owner.result.get().message == "Votre réponse a été postée avec succès !")
        let member = try await PostingHarness.run(form: "R123e") { flow, form async throws(PostingError) in
            try await flow.reply("group reply", with: form)
        }
        #expect(PostingHarness.pairs(of: try #require(member.body)).allSatisfy { $0.name != "newdest" })
    }
}
