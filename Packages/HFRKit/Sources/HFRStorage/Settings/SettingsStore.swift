/// Persistence of raw settings values, synchronous because SwiftUI and the renderers read settings inline.
///
/// Implementations are thread-safe. Only `SettingKey` entries and `LegacySettingsNormalizer` should call the raw methods.
public protocol SettingsStore: Sendable {
    /// The stored raw value, or nil when the key is absent or holds an unsupported type.
    func rawValue(forKey key: String) -> SettingRawValue?
    /// Stores a raw value.
    func setRawValue(_ value: SettingRawValue, forKey key: String)
    /// Removes the key.
    func removeValue(forKey key: String)
}

extension SettingsStore {
    /// The effective value of a setting: the stored one, normalised, or the default.
    public func value<Value>(for setting: Setting<Value>) -> Value {
        setting.value(from: rawValue(forKey: setting.key))
    }

    /// Stores a value; a setting that encodes it as nil has its key removed.
    public func set<Value>(_ value: Value, for setting: Setting<Value>) {
        if let raw = setting.rawValue(for: value) {
            setRawValue(raw, forKey: setting.key)
        } else {
            removeValue(forKey: setting.key)
        }
    }

    /// Removes the stored value so the default applies again.
    public func reset<Value>(_ setting: Setting<Value>) {
        removeValue(forKey: setting.key)
    }
}
