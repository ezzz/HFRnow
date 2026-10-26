/// A settings value as persisted: the four shapes `UserDefaults` holds for the legacy keys.
public enum SettingRawValue: Sendable, Hashable {
    /// A boolean.
    case bool(Bool)
    /// An integer.
    case int(Int)
    /// A floating-point number.
    case double(Double)
    /// A string.
    case string(String)
}
