/// Tolerant conversions between raw shapes, mirroring `UserDefaults`' `boolForKey:`, `integerForKey:` and `stringForKey:`.
enum SettingCoercion {
    /// The raw value has no boolean reading (thrown instead of returning an optional boolean).
    struct NotConvertible: Error {}

    /// Booleans accept numbers and the strings `1/0/true/false/yes/no/on/off` (legacy `AppHaptics.isEnabled`, `Common.swift:51-65`).
    static func bool(_ raw: SettingRawValue) throws -> Bool {
        switch raw {
        case .bool(let value):
            return value
        case .int(let value):
            return value != 0
        case .double(let value):
            guard value.isFinite else { throw NotConvertible() }
            return value != 0
        case .string(let text):
            return try boolean(fromWord: text)
        }
    }

    private static func boolean(fromWord text: String) throws -> Bool {
        switch text.trimmingWhitespace().lowercased() {
        case "1", "true", "yes", "on": return true
        case "0", "false", "no", "off": return false
        default: throw NotConvertible()
        }
    }

    /// Integers accept booleans, whole or fractional numbers (truncated like `integerForKey:`) and numeric strings.
    static func int(_ raw: SettingRawValue) -> Int? {
        switch raw {
        case .bool(let value):
            return value ? 1 : 0
        case .int(let value):
            return value
        case .double(let value):
            return int(truncating: value)
        case .string(let text):
            let trimmed = text.trimmingWhitespace()
            if let value = Int(trimmed) { return value }
            return Double(trimmed).flatMap { int(truncating: $0) }
        }
    }

    /// Doubles accept integers, booleans and numeric strings.
    static func double(_ raw: SettingRawValue) -> Double? {
        let value: Double?
        switch raw {
        case .bool(let flag): value = flag ? 1 : 0
        case .int(let number): value = Double(number)
        case .double(let number): value = number
        case .string(let text): value = Double(text.trimmingWhitespace())
        }
        return value.flatMap { $0.isFinite ? $0 : nil }
    }

    /// Strings accept numbers, as `stringForKey:` returns the description of an `NSNumber`.
    static func string(_ raw: SettingRawValue) -> String? {
        switch raw {
        case .bool(let value): value ? "1" : "0"
        case .int(let value): String(value)
        case .double(let value): value.isFinite ? String(value) : nil
        case .string(let value): value
        }
    }

    private static func int(truncating value: Double) -> Int? {
        guard value.isFinite, value > -9.2e18, value < 9.2e18 else { return nil }
        return Int(value)
    }
}

private extension String {
    func trimmingWhitespace() -> String {
        var slice = self[...]
        while let first = slice.first, first.isWhitespace { slice = slice.dropFirst() }
        while let last = slice.last, last.isWhitespace { slice = slice.dropLast() }
        return String(slice)
    }
}
