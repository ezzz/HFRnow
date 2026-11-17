import Foundation
import HFRStorage
import Observation

// Port of HFRswift/Swift/AppSettingsView.swift (AppSettingsView.notificationsSection, :527-531) @ 87fe0d1c. Differences: the
// check interval, the last check and the way to iOS's notification settings are new (GAP-190; operator decisions of 2026-11-07
// on #230).
/// Réglages › Notifications MP (LOT-140): the badge switch, the check interval and the last check of the current account.
@MainActor
@Observable
final class MPNotificationSettingsModel {
    /// "Badge messages non lus" (`mp_badge_enabled`, legacy default on).
    var badgeEnabled: Bool {
        didSet { store.set(badgeEnabled, for: SettingKey.privateMessageBadge) }
    }

    /// "Vérifier les messages" (`mp_check_interval`); a change schedules the next check again (or cancels it for Jamais).
    var interval: MPCheckInterval {
        didSet {
            guard interval != oldValue else { return }
            store.set(interval, for: SettingKey.mpCheckInterval)
            reschedule()
        }
    }

    /// When the current account was last checked in the background; nil before the first check or logged out.
    private(set) var lastCheck: Date?

    @ObservationIgnored private let store: any SettingsStore
    @ObservationIgnored private let ledger: NotificationLedgerStore
    @ObservationIgnored private let reschedule: @MainActor () -> Void

    /// Reads the values from `store`; nothing is written until one changes.
    init(
        store: any SettingsStore, ledger: NotificationLedgerStore = MPNotificationLedger.live,
        reschedule: @escaping @MainActor () -> Void = { MPBackgroundScheduler.schedule() }
    ) {
        self.store = store
        self.ledger = ledger
        self.reschedule = reschedule
        badgeEnabled = store.value(for: SettingKey.privateMessageBadge)
        interval = store.value(for: SettingKey.mpCheckInterval)
    }

    /// Reads the last check of `account` (the current account's key), nil when logged out.
    func loadLastCheck(account: String?) async {
        guard let account else {
            lastCheck = nil
            return
        }
        lastCheck = await ledger.ledger(for: account).lastCheck
    }

    /// « Dernière vérification : <heure> », the date too when it was not today; nil before the first check.
    func lastCheckText(now: Date = .now, calendar: Calendar = .current) -> String? {
        guard let lastCheck else { return nil }
        let time = lastCheck.formatted(date: .omitted, time: .shortened)
        guard calendar.isDate(lastCheck, inSameDayAs: now) else {
            return "Dernière vérification : \(lastCheck.formatted(date: .abbreviated, time: .omitted)) à \(time)"
        }
        return "Dernière vérification : \(time)"
    }
}
