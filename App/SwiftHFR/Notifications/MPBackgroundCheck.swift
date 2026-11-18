import Foundation
import HFRClient
import HFRModels
import HFRStorage
import OSLog

// Port of HFRswift/Swift/MPBackgroundService.swift (MPBackgroundService.performBackgroundCheck) @ 87fe0d1c. Differences: the
// current account's stored session instead of the shared jar, the per-account ledger (LOT-091) instead of `nb_mp`, one
// notification per conversation with news from MP list page 1, the icon badge set here too, nothing on an unknown or expired
// answer (GAP-190, GAP-191, GAP-192; operator decisions of 2026-11-07 on #230; docs/lots/LOT-140-background-mp-check.md); no
// notification while « Notifications » is off, the badge kept (operator, 2026-11-18, #1060).
/// One background MP check (LOT-140): due check, the forum's count and list, the ledger's news, notifications and badge.
struct MPBackgroundCheck: Sendable {
    /// The legacy text, kept for a count that went up while the list could not be read (`MPBackgroundService.swift:100`).
    static let legacyText = "Vous avez un nouveau message privé"
    /// Its own identifier, apart from the burst summary's, so withdrawing it never removes a summary.
    static let legacyIdentifier = "mp-legacy"
    /// Taken off the interval in the due test: iOS may launch the task right at its earliest date, which was computed a moment
    /// before the previous check stamped its own time, and a whole interval would be lost.
    static let schedulingSlack: TimeInterval = 60

    /// The current (main) account; nil when none is stored. Throws when the store cannot be read.
    let currentAccount: @Sendable () throws -> Account?
    let ledger: NotificationLedgerStore
    let settings: any SettingsStore
    let forum: any MPCheckForum
    let delivery: any MPNotificationDelivering

    private static let log = Logger(subsystem: "SwiftHFR", category: "MPBackgroundCheck")

    /// Runs one check at `now`. Sends at most two requests; sends none when the check is off, no account is stored or the
    /// last check is too recent. Shows no notification while « Notifications » is off (`mp_notifications_enabled`).
    @discardableResult
    func run(now: Date = .now) async -> MPCheckOutcome {
        let outcome = await check(now: now)
        Self.log.info("MP check: \(outcome.logLabel, privacy: .public)")
        return outcome
    }

    private func check(now: Date) async -> MPCheckOutcome {
        guard let interval = settings.value(for: SettingKey.mpCheckInterval).seconds else { return .disabled }
        guard let account = try? currentAccount() else { return .noAccount }
        // The interval guard shared with the App Intent (LOT-141); an unreadable ledger stops here, never loops (LOT-091).
        let minimum = max(interval - Self.schedulingSlack, 0)
        guard (try? await ledger.markCheckedIfDue(account: account.pseudo, now: now, minimumInterval: minimum)) == true else {
            return .notDue
        }
        let reading = await forum.read(as: account)
        guard let count = reading.count else { return .noInformation }
        let before = await ledger.ledger(for: account.pseudo)
        var summary = reading.page.map(MPNotificationLedger.seenSummary(of:)) ?? NotificationSummary()
        summary.unreadPrivateMessages = count
        guard let news = try? await ledger.recordNews(summary, account: account.pseudo) else {
            // Not recorded: notifying now would notify the same news again at the next run.
            return .noInformation
        }
        // « Notifications » off (#1060): the news is recorded as seen all the same, so turning it on never shows it late.
        let notifications = settings.value(for: SettingKey.mpNotificationsEnabled)
            ? Self.notifications(news: news, page: reading.page, hadCount: before.unreadPrivateMessages != nil) : []
        // A conversation's own notification says more than the legacy text an earlier run sent for it (list unreadable then).
        if notifications.contains(where: { $0.topic != nil }) { await delivery.withdraw(Self.legacyIdentifier) }
        for content in notifications { await delivery.deliver(content) }
        await delivery.setBadge(settings.value(for: SettingKey.privateMessageBadge) ? count : 0)
        return .checked(notifications: notifications.count)
    }

    /// The conversations with news, from the list. Without the list, the legacy text when the count went up from a count
    /// already recorded (a first check stays silent, as the ledger's thread baseline does). A list that was read and shows
    /// no new conversation sends nothing: the count alone can rise from a count the app recorded earlier (review r3).
    static func notifications(news: NotificationNews, page: PrivateMessageListPage?, hadCount: Bool) -> [MPNotificationContent] {
        if let page { return MPNotificationPlan.make(newThreads: news.newThreads, in: page).notifications }
        guard hadCount, news.newPrivateMessages > 0 else { return [] }
        return [MPNotificationContent(
            identifier: legacyIdentifier, threadIdentifier: legacyIdentifier, title: "", body: legacyText, topic: nil
        )]
    }
}

extension MPBackgroundCheck {
    /// The check the app runs: the Keychain accounts, the device's ledger, the settings, the forum, the notification center.
    static let live = MPBackgroundCheck(
        currentAccount: { try LiveCredentials.store.load().main },
        ledger: MPNotificationLedger.live,
        settings: UserDefaultsSettingsStore(),
        forum: LiveMPCheckForum(),
        delivery: MPNotificationCenter()
    )
}
