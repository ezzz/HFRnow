import Foundation
import HFRClient
import HFRModels
import HFRStorage
@testable import SwiftHFR
import Testing

/// LOT-140: the background check, from the setting to the notifications and the badge (spec "Check").
struct MPBackgroundCheckTests {
    private static let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private static let account = Account(pseudo: "fakeuser", isMain: true)

    struct Ready {
        let check: MPBackgroundCheck
        let forum: FakeMPCheckForum
        let delivery: FakeMPDelivery
        let ledger: NotificationLedgerStore
        let settings: InMemorySettingsStore
    }

    private func ready(
        _ readings: [MPForumReading], account: Account? = MPBackgroundCheckTests.account,
        settings: InMemorySettingsStore = InMemorySettingsStore(),
        ledger: NotificationLedgerStore = NotificationLedgerStore(persistence: InMemorySmallStorePersistence())
    ) -> Ready {
        let forum = FakeMPCheckForum(readings)
        let delivery = FakeMPDelivery()
        let check = MPBackgroundCheck(
            currentAccount: { account }, ledger: ledger, settings: settings, forum: forum, delivery: delivery
        )
        return Ready(check: check, forum: forum, delivery: delivery, ledger: ledger, settings: settings)
    }

    /// Runs `count` checks, each one interval after the previous.
    private func run(_ ready: Ready, times count: Int) async -> [MPCheckOutcome] {
        var outcomes: [MPCheckOutcome] = []
        for index in 0..<count {
            outcomes.append(await ready.check.run(now: Self.start.addingTimeInterval(Double(index) * 1800)))
        }
        return outcomes
    }

    @Test("Jamais: nothing is read, recorded or shown")
    func disabled() async {
        let settings = InMemorySettingsStore()
        settings.set(.never, for: SettingKey.mpCheckInterval)
        let ready = ready([MPForumReading(count: 1, page: mpPage(unread: [1]))], settings: settings)
        #expect(await ready.check.run(now: Self.start) == .disabled)
        #expect(ready.forum.reads.isEmpty)
        #expect(await ready.ledger.ledger(for: "fakeuser").lastCheck == nil)
        #expect(await ready.delivery.badges.isEmpty)
    }

    @Test("No stored account, or a store that cannot be read: nothing is read")
    func noAccount() async {
        let none = ready([MPForumReading(count: 1)], account: nil)
        #expect(await none.check.run(now: Self.start) == .noAccount)
        #expect(none.forum.reads.isEmpty)

        struct Unreadable: Error {}
        let forum = FakeMPCheckForum([MPForumReading(count: 1)])
        let failing = MPBackgroundCheck(
            currentAccount: { throw Unreadable() }, ledger: NotificationLedgerStore(persistence: InMemorySmallStorePersistence()),
            settings: InMemorySettingsStore(), forum: forum, delivery: FakeMPDelivery()
        )
        #expect(await failing.run(now: Self.start) == .noAccount)
        #expect(forum.reads.isEmpty)
    }

    @Test("A check sooner than the interval less one minute of slack reads nothing; one past it does (the ledger's guard)")
    func interval() async {
        let ready = ready([MPForumReading(count: 0, page: mpPage(unread: [])), MPForumReading(count: 0, page: mpPage(unread: []))])
        #expect(await ready.check.run(now: Self.start) == .checked(notifications: 0))
        #expect(await ready.check.run(now: Self.start.addingTimeInterval(1739)) == .notDue)
        #expect(ready.forum.reads == ["fakeuser"])
        // iOS launching the task right at its earliest date, computed just before the previous check stamped its time.
        #expect(await ready.check.run(now: Self.start.addingTimeInterval(1740)) == .checked(notifications: 0))
        #expect(ready.forum.reads == ["fakeuser", "fakeuser"])
    }

    @Test("No information (logged out, unknown page, expired, failure): no notification, no badge, nothing recorded")
    func noInformation() async {
        let ready = ready([
            MPForumReading(count: 2, page: mpPage(unread: [1])),
            MPForumReading(),
            MPForumReading(count: 2, page: mpPage(unread: [1, 2]))
        ])
        _ = await ready.check.run(now: Self.start)
        let before = await ready.ledger.ledger(for: "fakeuser")
        #expect(await ready.check.run(now: Self.start.addingTimeInterval(1800)) == .noInformation)
        #expect(await ready.delivery.delivered.isEmpty)
        #expect(await ready.delivery.badges == [2])
        let after = await ready.ledger.ledger(for: "fakeuser")
        #expect(after.unreadThreads == before.unreadThreads)
        #expect(after.unreadPrivateMessages == before.unreadPrivateMessages)
        // The baseline kept: the conversation that becomes unread afterwards is news.
        #expect(await ready.check.run(now: Self.start.addingTimeInterval(3600)) == .checked(notifications: 1))
        #expect(await ready.delivery.delivered.map(\.topic) == [2])
    }

    @Test("The first check is silent; a conversation that becomes unread is notified once; no change gives nothing")
    func newsOnce() async {
        let ready = ready([
            MPForumReading(count: 1, page: mpPage(unread: [10], read: [11])),
            MPForumReading(count: 2, page: mpPage(unread: [11, 10])),
            MPForumReading(count: 2, page: mpPage(unread: [11, 10]))
        ])
        #expect(await run(ready, times: 3) == [.checked(notifications: 0), .checked(notifications: 1), .checked(notifications: 0)])
        #expect(await ready.delivery.delivered == [
            MPNotificationContent(identifier: "mp-11", threadIdentifier: "mp-11", title: "pseudo11", body: "Sujet 11", topic: 11)
        ])
        #expect(await ready.delivery.badges == [1, 2, 2])
    }

    @Test("The badge follows the count, or 0 when the badge setting is off")
    func badgeSetting() async {
        let settings = InMemorySettingsStore()
        settings.set(false, for: SettingKey.privateMessageBadge)
        let ready = ready([MPForumReading(count: 3, page: mpPage(unread: [1, 2, 3]))], settings: settings)
        _ = await ready.check.run(now: Self.start)
        #expect(await ready.delivery.badges == [0])
    }

    @Test("Notifications off (#1060): news is recorded but nothing is shown or withdrawn; the badge still follows the count")
    func notificationsOff() async {
        let settings = InMemorySettingsStore()
        settings.set(false, for: SettingKey.mpNotificationsEnabled)
        let ready = ready([
            MPForumReading(count: 1, page: mpPage(unread: [10], read: [11])),
            MPForumReading(count: 2, page: mpPage(unread: [11, 10])),
            MPForumReading(count: 3, page: nil)
        ], settings: settings)
        #expect(await run(ready, times: 3) == [.checked(notifications: 0), .checked(notifications: 0), .checked(notifications: 0)])
        #expect(await ready.delivery.delivered.isEmpty)
        #expect(await ready.delivery.withdrawn.isEmpty)
        #expect(await ready.delivery.badges == [1, 2, 3])
        // Recorded as seen: turning notifications on again never shows this news late.
        #expect(await ready.ledger.ledger(for: "fakeuser").unreadPrivateMessages == 3)
    }

    @Test("The list could not be read: the count is recorded; a rise from a recorded count shows the legacy text, opening the list")
    func listUnreadable() async {
        let ready = ready([
            MPForumReading(count: 1, page: nil),
            MPForumReading(count: 1, page: nil),
            MPForumReading(count: 3, page: nil)
        ])
        // First check: no count recorded before, silent (as the thread baseline).
        #expect(await run(ready, times: 3) == [.checked(notifications: 0), .checked(notifications: 0), .checked(notifications: 1)])
        let shown = await ready.delivery.delivered
        #expect(shown.map(\.body) == [MPBackgroundCheck.legacyText])
        #expect(shown.map(\.topic) == [nil])
        #expect(await ready.ledger.ledger(for: "fakeuser").unreadPrivateMessages == 3)
    }

    @Test("A count the app recorded is not notified again by a check without the list")
    func countSeenInTheApp() async {
        let ready = ready([MPForumReading(count: 1, page: nil), MPForumReading(count: 3, page: nil)])
        _ = await ready.check.run(now: Self.start)
        await MPNotificationLedger.recordSeen(NotificationSummary(unreadPrivateMessages: 3), account: "fakeuser", store: ready.ledger)
        #expect(await ready.check.run(now: Self.start.addingTimeInterval(1800)) == .checked(notifications: 0))
        #expect(await ready.delivery.delivered.isEmpty)
    }

    @Test("A conversation the app showed unread on page 1 is not notified by the next check")
    func threadSeenInTheApp() async {
        let ready = ready([
            MPForumReading(count: 0, page: mpPage(unread: [], read: [5])), MPForumReading(count: 1, page: mpPage(unread: [5]))
        ])
        _ = await ready.check.run(now: Self.start)
        let seen = MPNotificationLedger.seenSummary(of: mpPage(unread: [5]))
        await MPNotificationLedger.recordSeen(seen, account: "fakeuser", store: ready.ledger)
        #expect(await ready.check.run(now: Self.start.addingTimeInterval(1800)) == .checked(notifications: 0))
        #expect(await ready.delivery.delivered.isEmpty)
    }

    @Test("The list was read and no conversation became unread: nothing, even when the count rose (review r3 #1)")
    func countRoseWithoutNewConversation() async {
        let ready = ready([
            MPForumReading(count: 1, page: mpPage(unread: [10])),
            MPForumReading(count: 2, page: mpPage(unread: [10]))
        ])
        #expect(await run(ready, times: 2) == [.checked(notifications: 0), .checked(notifications: 0)])
        #expect(await ready.delivery.delivered.isEmpty)
    }

    @Test("A conversation's notification withdraws the legacy text an earlier run sent while the list was unreadable")
    func conversationReplacesTheLegacyText() async {
        let ready = ready([
            MPForumReading(count: 0, page: mpPage(unread: [])),
            MPForumReading(count: 1, page: nil),
            MPForumReading(count: 1, page: mpPage(unread: [10]))
        ])
        #expect(await run(ready, times: 3) == [.checked(notifications: 0), .checked(notifications: 1), .checked(notifications: 1)])
        #expect(await ready.delivery.delivered.map(\.identifier) == ["mp-legacy", "mp-10"])
        #expect(await ready.delivery.withdrawn == ["mp-legacy"])
    }

    @Test("More than five conversations with news collapse into one summary that opens the list")
    func burst() async {
        let ready = ready([
            MPForumReading(count: 0, page: mpPage(unread: [])),
            MPForumReading(count: 6, page: mpPage(unread: [1, 2, 3, 4, 5, 6]))
        ])
        _ = await run(ready, times: 2)
        let shown = await ready.delivery.delivered
        #expect(shown.map(\.identifier) == ["mp-summary"])
        #expect(shown.map(\.body) == ["6 nouveaux messages privés"])
    }
}
