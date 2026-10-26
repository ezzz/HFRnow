import Synchronization

/// A settings store kept in memory, for tests and previews.
public final class InMemorySettingsStore: SettingsStore {
    private let storage: Mutex<[String: SettingRawValue]>

    /// Creates a store, optionally pre-filled (for example with legacy raw values).
    public init(_ initial: [String: SettingRawValue] = [:]) {
        storage = Mutex(initial)
    }

    public func rawValue(forKey key: String) -> SettingRawValue? {
        storage.withLock { $0[key] }
    }

    public func setRawValue(_ value: SettingRawValue, forKey key: String) {
        storage.withLock { $0[key] = value }
    }

    public func removeValue(forKey key: String) {
        storage.withLock { $0[key] = nil }
    }
}
