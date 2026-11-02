/// The iCloud key-value store, behind a protocol so the engine builds and tests on Linux (ADR 0013 §9, LOT-172).
///
/// `UbiquitousKeyValueStore` is the Apple implementation, `InMemorySyncedKeyValueStore` the one for tests and previews.
/// The engine never reads it on the hot path: `SyncedSettingsStore` keeps a `UserDefaults` mirror.
public protocol SyncedKeyValueStore: Sendable {
    /// The stored value, or nil when the key is absent or holds a shape the engine does not use.
    func value(forKey key: String) -> SyncedValue?
    /// Stores a value (the system uploads it later; last writer wins per key).
    func set(_ value: SyncedValue, forKey key: String)
    /// Removes the key.
    func removeValue(forKey key: String)
    /// Asks the system to exchange with iCloud now (launch, foreground). Returns false when it could not.
    @discardableResult
    func synchronize() -> Bool
    /// An opaque identity of the iCloud account whose values the store holds, to keep on the device; nil without an
    /// account.
    func accountIdentity() -> String?
    /// Whether `identity`, as returned by `accountIdentity()` at some point, is the account active now (nil: no account).
    func isCurrentAccount(_ identity: String?) -> Bool
    /// The external changes, in the order the system reports them. Each call returns its own stream.
    func changes() -> AsyncStream<SyncedStoreChange>
}

extension SyncedKeyValueStore {
    /// Compares identities as strings, for stores whose identity is stable as a string (the in-memory one).
    public func isCurrentAccount(_ identity: String?) -> Bool {
        accountIdentity() == identity
    }
}
