import Observation

// Port of HFRswift/Swift/Common.swift (MessagesNotificationNavigation.consumePendingOpenMessagesRequest) @ 87fe0d1c.
// Differences: the pending destination is held in memory, not in `UserDefaults`: a tap that launches the app reaches it
// before the root is built, and a tap is not replayed at the next launch (GAP-011).
/// The tap on an MP notification, held until the root navigation takes it (LOT-140).
@MainActor
@Observable
final class MPNotificationRouter {
    /// The one router of the app: the notification delegate writes it, the root reads it.
    static let shared = MPNotificationRouter()

    /// The last tap the root has not taken yet.
    private(set) var pending: MPNotificationDestination?

    /// Records a tap; a later one replaces an earlier one not yet taken.
    func receive(_ destination: MPNotificationDestination) {
        pending = destination
    }

    /// Takes the pending tap, once.
    func consume() -> MPNotificationDestination? {
        defer { pending = nil }
        return pending
    }
}
