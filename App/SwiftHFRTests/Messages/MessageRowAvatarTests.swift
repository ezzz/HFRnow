import Foundation
import HFRModels
import HFRParsing
@testable import SwiftHFR
import Testing

/// #714: which pseudo an MP row's avatar is read for, on the rows the parser really produces from the captured lists.
struct MessageRowAvatarTests {
    private static let listURL = "https://forum.hardware.fr/forum1.php?config=hfr.inc&cat=prive&page=1"

    private func threads(_ capture: String) throws -> [PrivateMessageThread] {
        let body = try LiveTopicPageSourceTests.capture(capture)
        return try PrivateMessageListParser.parse(try #require(String(data: body, encoding: .utf8)), pageURL: Self.listURL).threads
    }

    @Test("A one-to-one row shows its interlocutor's avatar; a group row keeps the group icon (R13u1 rows)")
    func capturedRows() throws {
        let rows = try threads("R13u1-mp-list-recipient-unread.html")
        let oneToOne = try #require(rows.first { !$0.isGroup })
        let subject = MessageRowView.avatarSubject(of: oneToOne)
        #expect(!subject.isGroup)
        #expect(subject.pseudo == oneToOne.summary.starterOrInterlocutors.trimmingCharacters(in: .whitespacesAndNewlines))
        #expect(subject.pseudo?.isEmpty == false)
        let group = try #require(rows.first { $0.isGroup })
        let groupSubject = MessageRowView.avatarSubject(of: group)
        #expect(groupSubject.isGroup && groupSubject.pseudo == nil)
    }

    @Test("A group row never leaks a member's pseudo (R123a)")
    func everyRow() throws {
        for name in ["R13u1-mp-list-recipient-unread.html", "R123a-mp-list-group-owner.html"] {
            for thread in try threads(name) {
                let subject = MessageRowView.avatarSubject(of: thread)
                #expect(subject.isGroup == thread.isGroup)
                #expect(subject.pseudo == nil || !thread.isGroup)
            }
        }
    }

    private func thread(starter: String, interlocutors: [String] = [], isGroup: Bool = false) -> PrivateMessageThread {
        let summary = TopicSummary(
            topicID: TopicID(category: .privateMessages, topic: 1), title: "t", path: "/forum2.php?config=hfr.inc&cat=prive&post=1",
            starterOrInterlocutors: starter
        )
        return PrivateMessageThread(summary: summary, interlocutors: interlocutors, isGroup: isGroup)
    }

    @Test("The interlocutor list wins over the starter cell, whitespace is trimmed, a blank name has no avatar")
    func normalisation() {
        #expect(MessageRowView.avatarSubject(of: thread(starter: "other", interlocutors: ["user2"])).pseudo == "user2")
        #expect(MessageRowView.avatarSubject(of: thread(starter: " user2 \n")).pseudo == "user2")
        #expect(MessageRowView.avatarSubject(of: thread(starter: "  ")).pseudo == nil)
        #expect(!MessageRowView.avatarSubject(of: thread(starter: "")).isGroup)
    }

    @Test("The label alone is a group, as in legacy; a pseudo that holds the word keeps their avatar")
    func multiplesLabel() {
        #expect(MessageRowView.avatarSubject(of: thread(starter: "Interlocuteurs multiples")).isGroup)
        #expect(!MessageRowView.avatarSubject(of: thread(starter: "multiples42")).isGroup)
        #expect(MessageRowView.avatarSubject(of: thread(starter: "multiples42")).pseudo == "multiples42")
    }
}
