import Foundation

/// Whether MPStorage sync runs for one HFR account (ADR 0013 §7): replaces the legacy app-wide `mpstorage_active`.
public enum MPStorageSyncState: String, Sendable, Hashable, Codable, CaseIterable {
    /// No choice yet (the default): the app looks for a storage thread, and asks at the first write when there is none.
    case unasked
    /// Sync runs: found a thread, or the member switched it on.
    case on
    /// The member answered no to the creation question; Réglages can switch it on later.
    case declined
    /// The member switched it off in Réglages.
    case off
}

/// The per-account record `mpstorage.<account key>` = `{state, decidedAt}` (ADR 0013 §7).
public struct MPStorageSyncRecord: Sendable, Hashable, Codable {
    /// The account's state.
    public var state: MPStorageSyncState
    /// When the state was decided; nil for the default `unasked`.
    public var decidedAt: Date?

    /// Creates a record.
    public init(state: MPStorageSyncState, decidedAt: Date? = nil) {
        self.state = state
        self.decidedAt = decidedAt
    }

    /// The record of an account nobody decided for yet.
    public static let unasked = MPStorageSyncRecord(state: .unasked)
}
