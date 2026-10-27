import Foundation
import Testing
@testable import HFRModels

/// LOT-023 models: invariants of the MP list types.
@Suite("Private message models")
struct PrivateMessageModelsTests {
    private static func summary(unread: Bool) -> TopicSummary {
        TopicSummary(
            topicID: TopicID(category: .privateMessages, topic: 3_207_033),
            title: "subject",
            path: "/forum2.php?config=hfr.inc&cat=prive&post=3207033",
            readState: unread ? .unread : .read
        )
    }

    @Test("Names in the tooltip imply the thread is unread by others, even if the flag was not set")
    func namesImplyMarker() {
        let thread = PrivateMessageThread(summary: Self.summary(unread: false), unreadBy: ["user2"])
        #expect(thread.isUnreadByOthers)
        #expect(!thread.isUnread)
        #expect(!PrivateMessageThread(summary: Self.summary(unread: false)).isUnreadByOthers)
    }

    @Test("A thread keeps the identity of its row; the page counts own unread threads only")
    func identityAndCount() {
        let page = PrivateMessageListPage(threads: [
            PrivateMessageThread(summary: Self.summary(unread: true)),
            PrivateMessageThread(summary: Self.summary(unread: false), isUnreadByOthers: true)
        ])
        #expect(page.threads[0].id == "topic:prive-3207033")
        #expect(page.unreadThreadCount == 1)
    }

    @Test("The page survives a Codable round trip")
    func codable() throws {
        let page = PrivateMessageListPage(
            threads: [
                PrivateMessageThread(summary: Self.summary(unread: true), unreadBy: ["a", "b"], interlocutors: ["a", "b"], isGroup: true)
            ],
            navigation: PageNavigation(current: 2, last: 7),
            newMessagePath: "/message.php?config=hfr.inc&cat=prive"
        )
        let decoded = try JSONDecoder().decode(PrivateMessageListPage.self, from: JSONEncoder().encode(page))
        #expect(decoded == page)
    }
}
