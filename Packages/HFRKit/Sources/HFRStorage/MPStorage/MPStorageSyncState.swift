import Foundation

/// Whether MPStorage sync runs for one HFR account (ADR 0013 §7): replaces the legacy app-wide `mpstorage_active`.
public enum MPStorageSyncState: String, Sendable, Hashable, Codable, CaseIterable {
    /// No choice yet (the default): the app looks for a storage thread, and asks at the first write when there is none.
    case unasked
    /// Sync runs: found a thread, or the member switched it on. Named as ADR 0013 §7 and stored as is in iCloud.
    case on // swiftlint:disable:this identifier_name - the ADR's name; a raw-value alias would read worse at every call site
    /// The member answered no to the creation question; Réglages can switch it on later.
    case declined
    /// The member switched it off in Réglages.
    case off
}

/// What MPStorage does for an account, one switch each (#859). Legacy had one switch for all (`mpstorage_active`).
public enum MPStorageFunction: String, Sendable, Hashable, CaseIterable {
    /// The shared blacklist (LOT-131).
    case blacklist
    /// Bookmarks of messages (LOT-132).
    case bookmarks
    /// The read position of group MPs, "MP multiples → dark topic" (#858).
    case mpFlags
}

/// The per-account record `mpstorage.<account key>` = `{state, decidedAt}` (ADR 0013 §7), plus, when a member switched a
/// function off, `disabled` (#859): the names of the functions off. Absent means every function on (legacy parity), so a
/// record written by an earlier build reads unchanged, and an earlier build ignores the field.
public struct MPStorageSyncRecord: Sendable, Hashable, Codable {
    /// The account's state.
    public var state: MPStorageSyncState
    /// When the state was decided; nil for the default `unasked`.
    public var decidedAt: Date?
    /// Raw names of the functions switched off; a name this build does not know (a newer build's function) is kept as is.
    public var disabled: [String]?

    /// Creates a record.
    public init(state: MPStorageSyncState, decidedAt: Date? = nil, disabled: [String]? = nil) {
        self.state = state
        self.decidedAt = decidedAt
        self.disabled = disabled?.isEmpty == true ? nil : disabled
    }

    /// Whether `function` is on for the account (the default).
    public func isEnabled(_ function: MPStorageFunction) -> Bool {
        !(disabled ?? []).contains(function.rawValue)
    }

    /// The record with `function` switched on or off; the other names, known or not, are kept.
    public func setting(_ function: MPStorageFunction, enabled: Bool) -> MPStorageSyncRecord {
        var names = (disabled ?? []).filter { $0 != function.rawValue }
        if !enabled { names.append(function.rawValue) }
        return MPStorageSyncRecord(state: state, decidedAt: decidedAt, disabled: names.sorted())
    }

    /// The record of an account nobody decided for yet.
    public static let unasked = MPStorageSyncRecord(state: .unasked)
}
