import Foundation

/// Synced values set aside when the iCloud account changed (ADR 0013 §3): device-only, never uploaded under another
/// account, restored only if their account becomes active again, deleted after `SyncedSettingsStore.quarantineLifetime`.
public struct SyncQuarantineDocument: SmallStoreDocument {
    /// Format version written by this code.
    public static let currentVersion = 1
    /// A document without any quarantined value.
    public static var empty: Self { Self() }

    /// Format version.
    public var version: Int
    /// Quarantined values keyed by the account identity they belong to (`SyncedKeyValueStore.accountIdentity()`).
    public var entries: [String: SyncQuarantineEntry]

    /// Creates a document.
    public init(version: Int = Self.currentVersion, entries: [String: SyncQuarantineEntry] = [:]) {
        self.version = version
        self.entries = entries
    }
}

/// The synced values one account held on this device when it stopped being the active one.
public struct SyncQuarantineEntry: Sendable, Hashable, Codable {
    /// When the values were set aside.
    public var savedAt: Date
    /// The values, by key.
    public var values: [String: SyncedValue]

    /// Creates an entry.
    public init(savedAt: Date, values: [String: SyncedValue]) {
        self.savedAt = savedAt
        self.values = values
    }
}
