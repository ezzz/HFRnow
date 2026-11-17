import Foundation
import HFRModels
import HFRParsing
import Testing
@testable import HFRClient

/// LOT-140: what the background check shows for the conversations the ledger reports as news, on captured MP lists.
@Suite("MP notification plan")
struct MPNotificationPlanTests {
    private static let listURL = "https://forum.hardware.fr/forum1.php?config=hfr.inc&cat=prive&page=1"

    private func page(_ capture: String) throws -> PrivateMessageListPage {
        try PrivateMessageListParser.parse(try Capture.page(capture), pageURL: Self.listURL)
    }

    /// The topic numbers of the unread rows, as the app hands them to the ledger.
    private func unread(_ page: PrivateMessageListPage) -> Set<Int> {
        Set(page.threads.filter(\.isUnread).compactMap { $0.summary.topicID?.topic })
    }

    private func thread(titled title: String, in page: PrivateMessageListPage) throws -> PrivateMessageThread {
        try #require(page.threads.first { $0.summary.title == title })
    }

    @Test("An older one-to-one row that became unread (R610a → R610b): one notification, the interlocutor over the title")
    func oneToOne() throws {
        let before = try page("R610a-mp-list-recipient-before-reply-older-row")
        let after = try page("R610b-mp-list-recipient-after-reply-older-row")
        let news = unread(after).subtracting(unread(before)).sorted()
        let row = try thread(titled: "fixture-test-5", in: after)
        let number = try #require(row.summary.topicID?.topic)
        #expect(news == [number])
        #expect(!row.isGroup)

        let plan = MPNotificationPlan.make(newThreads: news, in: after)
        let interlocutor = try #require(row.interlocutors.first)
        #expect(plan.notifications == [
            MPNotificationContent(
                identifier: "mp-\(number)", threadIdentifier: "mp-\(number)", title: HFRText.normalizedPseudo(interlocutor),
                body: "fixture-test-5", topic: number
            )
        ])
        #expect(!plan.notifications[0].title.isEmpty)
    }

    @Test("A group row that became unread in the creator's list (R610e → R610g): the conversation's title, no body")
    func group() throws {
        let before = try page("R610e-mp-list-group-creator-before-member-reply")
        let after = try page("R610g-mp-list-group-creator-after-member-reply")
        let row = try thread(titled: "fixture-test-7", in: after)
        let number = try #require(row.summary.topicID?.topic)
        #expect(row.isGroup)
        #expect(unread(after).subtracting(unread(before)).contains(number))

        let plan = MPNotificationPlan.make(newThreads: [number], in: after)
        #expect(plan.notifications == [
            MPNotificationContent(
                identifier: "mp-\(number)", threadIdentifier: "mp-\(number)", title: "fixture-test-7", body: "", topic: number
            )
        ])
    }

    @Test("Notifications follow the page's order, not the order of the news")
    func pageOrder() throws {
        let list = try page("R610b-mp-list-recipient-after-reply-older-row")
        let numbers = list.threads.prefix(3).compactMap { $0.summary.topicID?.topic }
        try #require(numbers.count == 3)
        let plan = MPNotificationPlan.make(newThreads: numbers.reversed(), in: list)
        #expect(plan.notifications.map(\.topic) == numbers)
    }

    @Test("Up to the burst limit each conversation has its own notification; one more collapses them into one summary")
    func burst() throws {
        let list = try page("R336-mp-list-recipient-unread-before-reply")
        let numbers = list.threads.compactMap { $0.summary.topicID?.topic }
        try #require(numbers.count > MPNotificationPlan.burstLimit)
        #expect(MPNotificationPlan.burstLimit == 5)

        let five = MPNotificationPlan.make(newThreads: Array(numbers.prefix(5)), in: list)
        #expect(five.notifications.count == 5)
        #expect(five.notifications.allSatisfy { $0.topic != nil })

        let six = MPNotificationPlan.make(newThreads: Array(numbers.prefix(6)), in: list)
        #expect(six.notifications == [
            MPNotificationContent(
                identifier: "mp-summary", threadIdentifier: "mp-summary", title: "Messages privés",
                body: "6 nouveaux messages privés", topic: nil
            )
        ])
    }

    @Test("A number the page does not list gives nothing, and no news gives nothing")
    func unknownAndEmpty() throws {
        let list = try page("R13u1-mp-list-recipient-unread")
        let listed = Set(list.threads.compactMap { $0.summary.topicID?.topic })
        let unknown = (listed.max() ?? 0) + 1
        #expect(MPNotificationPlan.make(newThreads: [unknown], in: list).notifications.isEmpty)
        #expect(MPNotificationPlan.make(newThreads: [], in: list).notifications.isEmpty)
        #expect(MPNotificationPlan.make(newThreads: [], in: list).isEmpty)
    }

    @Test("A conversation listed twice (a page that changed while served) gives one notification")
    func duplicateRow() throws {
        let list = try page("R610b-mp-list-recipient-after-reply-older-row")
        let row = try #require(list.threads.first)
        let number = try #require(row.summary.topicID?.topic)
        let doubled = PrivateMessageListPage(threads: [row, row])
        #expect(MPNotificationPlan.make(newThreads: [number], in: doubled).notifications.map(\.identifier) == ["mp-\(number)"])
    }

    @Test("The interlocutor of a one-to-one title loses the zero-width spaces HFR puts in long pseudos")
    func zeroWidthSpaces() {
        let topic = TopicID(category: .privateMessages, topic: 42)
        let row = PrivateMessageThread(
            summary: TopicSummary(topicID: topic, title: "Sujet", path: "/forum2.php?cat=prive&post=42", readState: .unread),
            interlocutors: ["long\u{200B}pseudo"]
        )
        let plan = MPNotificationPlan.make(newThreads: [42], in: PrivateMessageListPage(threads: [row]))
        #expect(plan.notifications.map(\.title) == ["longpseudo"])
        #expect(plan.notifications.map(\.body) == ["Sujet"])
    }
}
