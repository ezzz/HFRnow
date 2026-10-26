/// A typed settings key: the legacy `UserDefaults` name, the default and the tolerant codec between `Value` and the raw value.
///
/// Reading never fails: a missing, wrongly typed or out-of-range stored value yields `defaultValue` (or the
/// legacy normalisation of that value), as the legacy readers did through `integerForKey:` and friends.
public struct Setting<Value: Sendable>: Sendable {
    /// The `UserDefaults` key, identical to the legacy one so an update keeps the user's choices.
    public let key: String
    /// The value used while nothing usable is stored.
    public let defaultValue: Value
    private let decoder: @Sendable (SettingRawValue) -> Value?
    private let encoder: @Sendable (Value) -> SettingRawValue?

    /// Creates a setting. `decode` returns nil for a raw value it cannot use; `encode` returns nil to remove the key.
    public init(
        key: String,
        defaultValue: Value,
        decode: @escaping @Sendable (SettingRawValue) -> Value?,
        encode: @escaping @Sendable (Value) -> SettingRawValue?
    ) {
        self.key = key
        self.defaultValue = defaultValue
        self.decoder = decode
        self.encoder = encode
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
