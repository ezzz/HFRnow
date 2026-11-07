import Foundation

/// What the synced store keeps on this device only (ADR 0013 §3): the last iCloud account it saw, so an account change
/// made while the app was not running is seen at the next launch, and the values set aside at an account change, never
/// uploaded under another account, restored only if their account becomes active again, deleted after
/// `SyncedSettingsStore.quarantineLifetime`.
public struct SyncDeviceStateDocument: SmallStoreDocument {
    /// Format version written by this code.
    public static let currentVersion = 1
    /// A document of a device that never ran the synced store.
    public static var empty: Self { Self() }

    /// Format version.
    public var version: Int
    /// Whether `knownIdentity` was recorded (it is nil for "no account" too).
    public var identityRecorded: Bool
    /// The identity of the iCloud account last seen (`SyncedKeyValueStore.accountIdentity()`), nil for none.
    public var knownIdentity: String?
    /// Quarantined values keyed by the identity of the account they belong to.
    public var quarantine: [String: SyncQuarantineEntry]

    /// Creates a document.
    public init(
        version: Int = Self.currentVersion,
        identityRecorded: Bool = false,
        knownIdentity: String? = nil,
        quarantine: [String: SyncQuarantineEntry] = [:]
    ) {
        self.version = version
        self.identityRecorded = identityRecorded
        self.knownIdentity = knownIdentity
        self.quarantine = quarantine
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
