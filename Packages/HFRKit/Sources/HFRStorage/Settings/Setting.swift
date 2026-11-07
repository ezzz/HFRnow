/// Where a setting's value lives (ADR 0013 §1, matrix E): the device only, or the iCloud key-value store with the local
/// `UserDefaults` value as its mirror (LOT-172).
public enum SettingScope: Sendable, Hashable {
    /// A device presentation or capability preference, transient UI state, or a key no longer written: never synced.
    case device
    /// A content preference that follows the Apple ID.
    case synced
}

/// What the catalogue needs of a setting whatever its value type.
public protocol CatalogueSetting: Sendable {
    /// The `UserDefaults` key.
    var key: String { get }
    /// Where the value lives.
    var scope: SettingScope { get }
}

/// A typed settings key: the legacy `UserDefaults` name, the default and the tolerant codec between `Value` and the raw value.
///
/// Reading never fails: a missing, wrongly typed or out-of-range stored value yields `defaultValue` (or the
/// legacy normalisation of that value), as the legacy readers did through `integerForKey:` and friends.
public struct Setting<Value: Sendable>: CatalogueSetting {
    /// The `UserDefaults` key, identical to the legacy one so an update keeps the user's choices.
    public let key: String
    /// The value used while nothing usable is stored.
    public let defaultValue: Value
    /// Where the value lives; `.device` unless the ADR 0013 matrix says the setting syncs.
    public let scope: SettingScope
    private let decoder: @Sendable (SettingRawValue) -> Value?
    private let encoder: @Sendable (Value) -> SettingRawValue?

    /// Creates a setting. `decode` returns nil for a raw value it cannot use; `encode` returns nil to remove the key.
    public init(
        key: String,
        defaultValue: Value,
        scope: SettingScope = .device,
        decode: @escaping @Sendable (SettingRawValue) -> Value?,
        encode: @escaping @Sendable (Value) -> SettingRawValue?
    ) {
        self.key = key
        self.defaultValue = defaultValue
        self.scope = scope
        self.decoder = decode
        self.encoder = encode
    }

    /// The same setting, synced through the iCloud key-value store (ADR 0013).
    public var synced: Setting<Value> {
        Setting(key: key, defaultValue: defaultValue, scope: .synced, decode: decoder, encode: encoder)
    }

    /// The effective value for a stored raw value (nil means "not stored").
    public func value(from raw: SettingRawValue?) -> Value {
        guard let raw, let decoded = decoder(raw) else { return defaultValue }
        return decoded
    }

    /// The raw value to persist for `value`, or nil when the key must be removed.
    public func rawValue(for value: Value) -> SettingRawValue? {
        encoder(value)
    }
}
