import OSLog
import UserNotifications

/// What iOS allows the app to show (#1060): read from Réglages › Notifications of iOS, never stored.
struct NotificationPermission: Sendable, Equatable {
    /// The member's answer to the permission prompt.
    enum Authorization: Sendable, Equatable {
        /// Never asked: the system prompt can still be shown.
        case notDetermined
        /// Refused, or turned off in iOS's settings: only those settings can change it.
        case denied
        /// Allowed, provisionally or for good.
        case allowed
    }

    let authorization: Authorization
    /// Whether iOS shows the icon badge (« Pastilles »).
    let badgesAllowed: Bool
}

/// Reads and asks for the notification permission: the seam the settings tests replace (`LiveNotificationPermission`).
protocol NotificationPermissionReading: Sendable {
    /// iOS's current settings for the app.
    func current() async -> NotificationPermission
    /// Shows the system prompt; iOS answers at once without it when the member already chose.
    func requestAuthorization() async
}

/// The live permission, from `UNUserNotificationCenter`.
struct LiveNotificationPermission: NotificationPermissionReading {
    private static let log = Logger(subsystem: "SwiftHFR", category: "NotificationPermission")

    func current() async -> NotificationPermission {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let authorization: NotificationPermission.Authorization = switch settings.authorizationStatus {
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .authorized, .provisional, .ephemeral: .allowed
        @unknown default: .allowed
        }
        return NotificationPermission(authorization: authorization, badgesAllowed: settings.badgeSetting == .enabled)
    }

    func requestAuthorization() async {
        do {
            // The options of the launch request (`MPNotificationCenter.prepare`).
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            Self.log.error("Notification authorization failed")
        }
    }
}
