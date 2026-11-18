import Foundation
import HFRStorage
import Observation

// Port of HFRswift/Swift/AppSettingsView.swift (AppSettingsView.notificationsSection, :527-531) @ 87fe0d1c. Differences: the
// check interval, the last check and the way to iOS's notification settings are new (GAP-190; operator decisions of 2026-11-07
// on #230); so are the « Notifications » switch and the alert when a switch disagrees with iOS (operator, 2026-11-18, #1060).
/// Réglages › Notifications MP (LOT-140): the notifications and badge switches, the check interval, the last check of the
/// current account, and the alert when a switch is on while iOS does not show what it asks for (#1060).
@MainActor
@Observable
final class MPNotificationSettingsModel {
    /// « Notifications » (`mp_notifications_enabled`, default on): off, the background check shows no notification.
    var notificationsEnabled: Bool {
        didSet { store.set(notificationsEnabled, for: SettingKey.mpNotificationsEnabled) }
    }

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

    /// The alert on screen; the view sets it back to nil when it is dismissed.
    var alert: MPNotificationSettingsAlert?

    /// One automatic alert per opening of the section (the model lives as long as the screen): back from iOS's settings
    /// with nothing changed, it is not shown again.
    @ObservationIgnored private var alertShown = false

    @ObservationIgnored private let store: any SettingsStore
    @ObservationIgnored private let ledger: NotificationLedgerStore
    @ObservationIgnored private let reschedule: @MainActor () -> Void
    @ObservationIgnored private let permission: any NotificationPermissionReading

    /// Reads the values from `store`; nothing is written until one changes.
    init(
        store: any SettingsStore, ledger: NotificationLedgerStore = MPNotificationLedger.live,
        reschedule: @escaping @MainActor () -> Void = { Task { await MPBackgroundScheduler.schedule() } },
        permission: any NotificationPermissionReading = LiveNotificationPermission()
    ) {
        self.store = store
        self.ledger = ledger
        self.reschedule = reschedule
        self.permission = permission
        notificationsEnabled = store.value(for: SettingKey.mpNotificationsEnabled)
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

    // MARK: Agreement with iOS (#1060)

    /// On opening the section and on coming back to the app: the first switch iOS contradicts, once per opening.
    func checkPermission() async {
        guard !alertShown else { return }
        let current = await permission.current()
        guard !alertShown else { return }
        show(Self.disagreement(notifications: notificationsEnabled, badge: badgeEnabled, with: current))
    }

    /// « Notifications » just turned on: asks iOS when it never asked, else the alert when iOS refuses.
    func notificationsTurnedOn() async {
        let current = await permission.current()
        guard notificationsEnabled else { return }
        switch current.authorization {
        case .notDetermined: await permission.requestAuthorization()
        case .denied: show(.notifications)
        case .allowed: break
        }
    }

    /// « Badge messages non lus » just turned on: the alert when iOS does not show the badge.
    func badgeTurnedOn() async {
        let current = await permission.current()
        guard badgeEnabled else { return }
        show(Self.disagreement(notifications: false, badge: true, with: current))
    }

    /// The alert a pair of switches calls for: notifications refused first, then a badge iOS does not show; none while
    /// iOS never asked (the system prompt comes first).
    static func disagreement(notifications: Bool, badge: Bool, with permission: NotificationPermission) -> MPNotificationSettingsAlert? {
        if notifications, permission.authorization == .denied { return .notifications }
        if badge, permission.authorization != .notDetermined, !permission.badgesAllowed { return .badge }
        return nil
    }

    private func show(_ alert: MPNotificationSettingsAlert?) {
        guard let alert else { return }
        alertShown = true
        self.alert = alert
    }
}

/// The alert of Réglages › Notifications MP when a switch is on while iOS does not show what it asks for (#1060).
enum MPNotificationSettingsAlert: Sendable, Equatable {
    /// « Notifications » on, notifications refused in iOS.
    case notifications
    /// « Badge messages non lus » on, badges off in iOS.
    case badge

    /// The alert's title.
    var title: String { "Notifications désactivées dans iOS" }

    /// The alert's message.
    var message: String {
        switch self {
        case .notifications: "Autorisez SwiftHFR dans Réglages › Notifications pour recevoir les messages privés."
        case .badge: "Autorisez SwiftHFR dans Réglages › Notifications pour voir la pastille sur l'icône."
        }
    }
}
