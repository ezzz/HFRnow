/// A change the iCloud key-value store reports (`NSUbiquitousKeyValueStoreDidChangeExternallyNotification`).
public struct SyncedStoreChange: Sendable, Hashable {
    /// Why the store changed (`NSUbiquitousKeyValueStoreChangeReasonKey`).
    public enum Reason: Sendable, Hashable {
        /// Another device wrote the keys.
        case serverChange
        /// The first download for this device's iCloud account completed.
        case initialSync
        /// The app went over its quota; the store refused the keys.
        case quotaViolation
        /// The iCloud account changed or signed out: the store now holds another account's values (or none).
        case accountChange
    }

    /// Why.
    public let reason: Reason
    /// The keys concerned (`NSUbiquitousKeyValueStoreChangedKeysKey`).
    public let keys: [String]

    /// Creates a change.
    public init(reason: Reason, keys: [String] = []) {
        self.reason = reason
        self.keys = keys
    }
}
