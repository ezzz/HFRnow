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

    /// Registers the category, then asks for permission as legacy does at every launch (`HFRswiftApp.swift:27-29`): iOS
    /// shows the prompt once and answers from the member's choice afterwards.
    func prepare() async {
        let center = UNUserNotificationCenter.current()
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Self.categoryIdentifier, actions: [], intentIdentifiers: [],
                hiddenPreviewsBodyPlaceholder: "%u nouveaux messages privés", options: []
            )
        ])
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            Self.log.error("Notification authorization failed")
        }
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

    func setBadge(_ count: Int) async {
        do {
            try await UNUserNotificationCenter.current().setBadgeCount(max(count, 0))
        } catch {
            Self.log.error("Badge not set")
        }
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
