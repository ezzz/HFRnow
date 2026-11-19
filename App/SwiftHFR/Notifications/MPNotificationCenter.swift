import HFRClient
import OSLog
import UserNotifications

// Port of HFRswift/Swift/MPBackgroundService.swift (requestNotificationAuthorization, updateAppIconBadge, scheduleNotification)
// @ 87fe0d1c. Differences: the identifier and thread identifier of `MPNotificationPlan` instead of a random one, the `mp`
// category for hidden previews, delivered at once instead of after 3 s (GAP-191; operator decisions of 2026-11-07 on #230).
/// The live notification center of the MP check: permission, the `mp` category, notifications and the icon badge.
struct MPNotificationCenter: MPNotificationDelivering {
    /// The category of every MP notification: its placeholder replaces the text when iOS hides previews.
    static let categoryIdentifier = "mp"

    private static let log = Logger(subsystem: "SwiftHFR", category: "MPNotificationCenter")

    /// Registers the category at launch. The permission is not asked here (legacy asked at every launch,
    /// `HFRswiftApp.swift:27-29` @ 87fe0d1c): `MPNotificationPrompt` asks once an account is current (#1172).
    static func registerCategory() {
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(
                identifier: categoryIdentifier, actions: [], intentIdentifiers: [],
                hiddenPreviewsBodyPlaceholder: "%u nouveaux messages privés", options: []
            )
        ])
    }

    func deliver(_ content: MPNotificationContent) async {
        let request = UNNotificationRequest(identifier: content.identifier, content: Self.content(content), trigger: nil)
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            Self.log.error("Notification not added")
        }
    }

    func withdraw(_ identifier: String) async {
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    @discardableResult
    func setBadge(_ count: Int) async -> Bool {
        let center = UNUserNotificationCenter.current()
        // Read before the write: the first launch's count can come while the permission prompt is still on screen (#1060).
        let allowed = await center.notificationSettings().badgeSetting == .enabled
        do {
            try await center.setBadgeCount(max(count, 0))
        } catch {
            Self.log.error("Badge not set")
            return false
        }
        return allowed
    }

    /// The system content: no message text, sound default, `.active` (never time-sensitive), and where a tap leads.
    static func content(_ content: MPNotificationContent) -> UNMutableNotificationContent {
        let system = UNMutableNotificationContent()
        system.title = content.title
        system.body = content.body
        system.threadIdentifier = content.threadIdentifier
        system.categoryIdentifier = categoryIdentifier
        system.sound = .default
        system.interruptionLevel = .active
        system.userInfo = MPNotificationDestination(topic: content.topic).userInfo
        return system
    }
}
