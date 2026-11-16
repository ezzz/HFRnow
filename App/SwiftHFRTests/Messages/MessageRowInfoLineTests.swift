@testable import SwiftHFR
import Foundation
import HFRModels
import Testing

struct MessageRowInfoLineTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func thread(
        group: Bool, starter: String = "membre", last: LastPost? = nil, unreadBy: [String] = []
    ) -> PrivateMessageThread {
        let summary = TopicSummary(
            topicID: TopicID(category: .privateMessages, topic: 3_207_033),
            title: "subject", path: "/forum2.php?config=hfr.inc&cat=prive&post=3207033",
            lastPost: last, starterOrInterlocutors: starter
        )
        return PrivateMessageThread(summary: summary, unreadBy: unreadBy, isUnreadByOthers: !unreadBy.isEmpty, isGroup: group)
    }

    private func post(_ author: String, minutesAgo: Double?) -> LastPost {
        LastPost(author: author, path: "/p", date: minutesAgo.map { now.addingTimeInterval(-$0 * 60) })
    }

    @Test("A one-to-one row: the interlocutor on the left, « last poster - time » on the right")
    func oneToOne() {
        let row = thread(group: false, last: post("autre", minutesAgo: 5))
        let line = MessageRowInfoLine.make(thread: row, flagLabel: "⚑ 1 / 2", now: now)
        #expect(line.leading == "membre")
        #expect(line.trailing == "autre - 5 min")
    }

    @Test("A group row: the flag on the left, never « Interlocuteurs multiples », even with that label as the starter")
    func group() {
        let group = thread(group: true, starter: "Interlocuteurs multiples", last: post("autre", minutesAgo: 90))
        #expect(MessageRowInfoLine.make(thread: group, flagLabel: "⚑ 2 / 3", now: now).leading == "⚑ 2 / 3")
        #expect(MessageRowInfoLine.make(thread: group, flagLabel: nil, now: now).leading == nil)
    }

    @Test("« x min » under 2 h, « x h » under 24 h, the date beyond")
    func timeFormats() {
        #expect(MessageRowInfoLine.age(of: now.addingTimeInterval(-10), now: now) == "1 min")
        #expect(MessageRowInfoLine.age(of: now.addingTimeInterval(-119 * 60), now: now) == "119 min")
        #expect(MessageRowInfoLine.age(of: now.addingTimeInterval(-120 * 60), now: now) == "2 h")
        #expect(MessageRowInfoLine.age(of: now.addingTimeInterval(-23.9 * 3600), now: now) == "23 h")
        #expect(MessageRowInfoLine.age(of: now.addingTimeInterval(-24 * 3600), now: now) == "14/01/2027")
        #expect(MessageRowInfoLine.age(of: now.addingTimeInterval(60), now: now) == "1 min")
    }

    @Test("A post without a date shows its author alone; no post shows nothing on the right")
    func undatedAndAbsent() {
        let undated = thread(group: false, last: post("autre", minutesAgo: nil))
        #expect(MessageRowInfoLine.make(thread: undated, flagLabel: nil, now: now).trailing == "autre")
        #expect(MessageRowInfoLine.make(thread: thread(group: false), flagLabel: nil, now: now).trailing == nil)
    }

    @Test("A row whose list cell says « Interlocuteurs multiples » is a group: the flag, never that label")
    func groupLabelWithoutTooltip() {
        let row = thread(group: false, starter: "Interlocuteurs multiples")
        #expect(MessageRowInfoLine.make(thread: row, flagLabel: "⚑ 1 / 2", now: now).leading == "⚑ 1 / 2")
        #expect(MessageRowInfoLine.make(thread: row, flagLabel: nil, now: now).leading == nil)
    }
}
