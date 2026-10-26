import Foundation

/// The settings store backed by `UserDefaults`; with the standard suite it reads what the legacy app wrote.
///
/// It never calls `register(defaults:)`: defaults live in `Setting`, so no volatile state is hidden in the process (E §7.1).
public final class UserDefaultsSettingsStore: SettingsStore, @unchecked Sendable {
    // UserDefaults is documented as thread-safe; the class stays immutable after init.
    private let defaults: UserDefaults

    /// Creates a store over `defaults` (the standard suite by default).
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func rawValue(forKey key: String) -> SettingRawValue? {
        guard let object = defaults.object(forKey: key) else { return nil }
        if let text = object as? String { return .string(text) }
        guard let number = object as? NSNumber else { return nil }
        switch String(cString: number.objCType) {
        case "c", "B": return .bool(number.boolValue)
        case "d", "f": return .double(number.doubleValue)
        default: return .int(number.intValue)
        }
    }

    public func setRawValue(_ value: SettingRawValue, forKey key: String) {
        switch value {
        case .bool(let flag): defaults.set(flag, forKey: key)
        case .int(let number): defaults.set(number, forKey: key)
        case .double(let number): defaults.set(number, forKey: key)
        case .string(let text): defaults.set(text, forKey: key)
        }
    }

    public func removeValue(forKey key: String) {
        defaults.removeObject(forKey: key)
    }
}
