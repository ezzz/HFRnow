@testable import SwiftHFR
import HFRModels
import SwiftUI
import Testing

struct MessageRowCuesTests {
    @Test("An unread row is tinted, a read one is not")
    func unreadTint() {
        #expect(MessageRowView.rowTint(isUnread: true, isSelected: false) != nil)
        #expect(MessageRowView.rowTint(isUnread: false, isSelected: false) == nil)
    }

    @Test("The selected row keeps the system selection highlight")
    func selectedRowIsNotTinted() {
        #expect(MessageRowView.rowTint(isUnread: true, isSelected: true) == nil)
    }

    private func thread(unread: Bool, unreadBy: [String] = [], marked: Bool = false) -> PrivateMessageThread {
        let summary = TopicSummary(
            topicID: TopicID(category: .privateMessages, topic: 3_207_033),
            title: "subject",
            path: "/forum2.php?config=hfr.inc&cat=prive&post=3207033",
            readState: unread ? .unread : .read
        )
        return PrivateMessageThread(summary: summary, unreadBy: unreadBy, isUnreadByOthers: marked)
    }

    @Test("The \"non lu\" capsule follows the correspondent's state only, with its label")
    func unreadByOthersLabel() {
        #expect(MessageRowView.unreadByLabel(thread(unread: true)) == nil)
        #expect(MessageRowView.unreadByLabel(thread(unread: false, marked: true)) == "Non lu par le destinataire")
        #expect(MessageRowView.unreadByLabel(thread(unread: true, unreadBy: ["user1", "user2"])) == "Non lu par user1, user2")
    }
}
