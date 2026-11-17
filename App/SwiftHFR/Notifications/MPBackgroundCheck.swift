import Foundation
import HFRClient
import HFRModels
import HFRStorage
import OSLog

// Port of HFRswift/Swift/MPBackgroundService.swift (MPBackgroundService.performBackgroundCheck) @ 87fe0d1c. Differences: the
// current account's stored session instead of the shared jar, the per-account ledger (LOT-091) instead of `nb_mp`, one
// notification per conversation with news from MP list page 1, the icon badge set here too, nothing on an unknown or expired
// answer (GAP-190, GAP-191, GAP-192; operator decisions of 2026-11-07 on #230; docs/lots/LOT-140-background-mp-check.md).
/// One background MP check (LOT-140): due check, the forum's count and list, the ledger's news, notifications and badge.
struct MPBackgroundCheck: Sendable {
    /// The legacy text, kept for a count that went up while the list could not be read (`MPBackgroundService.swift:100`).
    static let legacyText = "Vous avez un nouveau message privé"

    /// The current (main) account; nil when none is stored. Throws when the store cannot be read.
    let currentAccount: @Sendable () throws -> Account?
    let ledger: NotificationLedgerStore
    let settings: any SettingsStore
    let forum: any MPCheckForum
    let delivery: any MPNotificationDelivering

    private static let log = Logger(subsystem: "SwiftHFR", category: "MPBackgroundCheck")

    /// Runs one check at `now`. Sends at most two requests; sends none when the check is off, no account is stored or the
    /// last check is too recent.
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
        guard (try? await ledger.markCheckedIfDue(account: account.pseudo, now: now, minimumInterval: interval)) == true else {
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
        let notifications = Self.notifications(news: news, page: reading.page, hadCount: before.unreadPrivateMessages != nil)
        for content in notifications { await delivery.deliver(content) }
        await delivery.setBadge(settings.value(for: SettingKey.privateMessageBadge) ? count : 0)
        return .checked(notifications: notifications.count)
    }

    /// The conversations with news, from the list; without the list, the legacy text when the count went up from a count
    /// already recorded (a first check stays silent, as the ledger's thread baseline does).
    static func notifications(news: NotificationNews, page: PrivateMessageListPage?, hadCount: Bool) -> [MPNotificationContent] {
        if let page { return MPNotificationPlan.make(newThreads: news.newThreads, in: page).notifications }
        guard hadCount, news.newPrivateMessages > 0 else { return [] }
        return [MPNotificationContent(
            identifier: MPNotificationPlan.summaryIdentifier, threadIdentifier: MPNotificationPlan.summaryIdentifier,
            title: "", body: legacyText, topic: nil
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
