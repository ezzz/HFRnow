import HFRStorage

// Port of HFRswift/Swift/HFRswiftApp.swift (the launch `.task` calling `requestNotificationAuthorization`, :27-29) @ 87fe0d1c.
// Differences: asked when an account becomes current instead of at every launch (HIG › Privacy, « Requesting permission »;
// GAP-1172, #1172).
/// When the app shows iOS's notification prompt: once an account is current (a stored one restored, a login, a switch), while
/// iOS never asked and « Notifications » or « Badge messages non lus » is on. Logged out, nothing the app would show needs it;
/// Réglages › Notifications MP still asks when a switch is turned on (`MPNotificationSettingsModel.notificationsTurnedOn`).
@MainActor
struct MPNotificationPrompt {
    let store: any SettingsStore
    let permission: any NotificationPermissionReading

    /// The app's prompt, over the stored settings and iOS.
    static let live = MPNotificationPrompt(store: UserDefaultsSettingsStore(), permission: LiveNotificationPermission())

    /// `account` (its key, nil when logged out) became current: shows the prompt when the rule says so. iOS shows it once.
    func accountBecameCurrent(_ account: String?) async {
        let notifications = store.value(for: SettingKey.mpNotificationsEnabled)
        let badge = store.value(for: SettingKey.privateMessageBadge)
        guard account != nil, notifications || badge else { return }
        let current = await permission.current()
        guard Self.asks(account: account, notifications: notifications, badge: badge, authorization: current.authorization)
        else { return }
        await permission.requestAuthorization()
    }

    /// The rule on its inputs: an account, a switch that needs the permission, and iOS never asked.
    static func asks(
        account: String?, notifications: Bool, badge: Bool, authorization: NotificationPermission.Authorization
    ) -> Bool {
        account != nil && (notifications || badge) && authorization == .notDetermined
    }
}
