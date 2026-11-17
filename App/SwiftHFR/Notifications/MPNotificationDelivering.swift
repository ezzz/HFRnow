import HFRClient

/// Where the background check shows what it found: the seam its tests replace (`MPNotificationCenter` in the app).
protocol MPNotificationDelivering: Sendable {
    /// Shows `content`; one with the same identifier replaces it.
    func deliver(_ content: MPNotificationContent) async
    /// Removes the notification with `identifier`, shown or pending.
    func withdraw(_ identifier: String) async
    /// Sets the app icon badge; 0 hides it.
    func setBadge(_ count: Int) async
}
