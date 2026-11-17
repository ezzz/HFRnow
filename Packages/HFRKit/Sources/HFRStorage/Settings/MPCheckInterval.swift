import Foundation

/// How often the background MP check may run (LOT-140, Réglages › Notifications MP › "Vérifier les messages"): a minimum
/// between two checks, never a promise, since iOS picks the real moment (operator, 2026-11-07 on #230). Stored in minutes.
public enum MPCheckInterval: Int, Sendable, CaseIterable {
    case fifteenMinutes = 15
    case thirtyMinutes = 30
    case oneHour = 60
    case twoHours = 120
    case fourHours = 240
    /// No background check.
    case never = 0

    /// The minimum delay between two checks; nil for `never`.
    public var seconds: TimeInterval? {
        self == .never ? nil : TimeInterval(rawValue * 60)
    }
}
