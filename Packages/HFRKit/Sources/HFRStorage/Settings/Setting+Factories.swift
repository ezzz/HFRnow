extension Setting where Value == Bool {
    /// A boolean setting stored as a boolean, read tolerantly.
    public static func bool(_ key: String, default defaultValue: Bool) -> Setting<Bool> {
        Setting(key: key, defaultValue: defaultValue, decode: { try? SettingCoercion.bool($0) }, encode: { .bool($0) })
    }
}

extension Setting where Value == Int {
    /// An integer setting; values for which `isValid` is false read as the default (legacy "forced if <= 0" rules).
    public static func int(
        _ key: String,
        default defaultValue: Int,
        isValid: @escaping @Sendable (Int) -> Bool = { _ in true }
    ) -> Setting<Int> {
        Setting(
            key: key,
            defaultValue: defaultValue,
            decode: { SettingCoercion.int($0).flatMap { isValid($0) ? $0 : nil } },
            encode: { .int($0) }
        )
    }
}

extension Setting where Value == String {
    /// A string setting.
    public static func string(_ key: String, default defaultValue: String) -> Setting<String> {
        Setting(key: key, defaultValue: defaultValue, decode: SettingCoercion.string, encode: { .string($0) })
    }
}

extension Setting where Value == String? {
    /// An optional string setting: nil means "nothing stored", which removes the key.
    public static func optionalString(_ key: String) -> Setting<String?> {
        Setting(
            key: key,
            defaultValue: nil,
            decode: { SettingCoercion.string($0).flatMap { $0.isEmpty ? nil : $0 } },
            encode: { $0.map { .string($0) } }
        )
    }
}

extension Setting where Value == Double? {
    /// An optional number setting: nil means "nothing stored", which removes the key.
    public static func optionalDouble(_ key: String) -> Setting<Double?> {
        Setting(key: key, defaultValue: nil, decode: { SettingCoercion.double($0) }, encode: { $0.map { .double($0) } })
    }
}

extension Setting where Value: RawRepresentable & Sendable, Value.RawValue == Int {
    /// An enum setting stored as its integer raw value. `fallback` maps an integer without a case (default: the default value).
    public static func integerEnum(
        _ key: String,
        default defaultValue: Value,
        fallback: (@Sendable (Int) -> Value?)? = nil
    ) -> Setting<Value> {
        Setting(
            key: key,
            defaultValue: defaultValue,
            decode: { raw in SettingCoercion.int(raw).flatMap { Value(rawValue: $0) ?? fallback?($0) } },
            encode: { .int($0.rawValue) }
        )
    }
}

extension Setting where Value: RawRepresentable & Sendable, Value.RawValue == String {
    /// An enum setting stored as its string raw value. `fallback` maps a string without a case (default: the default value).
    public static func stringEnum(
        _ key: String,
        default defaultValue: Value,
        fallback: (@Sendable (String) -> Value?)? = nil
    ) -> Setting<Value> {
        Setting(
            key: key,
            defaultValue: defaultValue,
            decode: { raw in SettingCoercion.string(raw).flatMap { Value(rawValue: $0) ?? fallback?($0) } },
            encode: { .string($0.rawValue) }
        )
    }
}
