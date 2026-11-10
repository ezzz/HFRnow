import Foundation

/// A property-list value read from the legacy container (`UserDefaults`, plist files), in a `Sendable` form.
public enum LegacyValue: Sendable, Hashable {
    case string(String)
    case integer(Int)
    case real(Double)
    case bool(Bool)
    case data(Data)
    case date(Date)
    case array([LegacyValue])
    case dictionary([String: LegacyValue])

    /// Converts what `UserDefaults` or `PropertyListSerialization` returned; nil for any other type.
    public init?(propertyList value: Any) {
        switch value {
        case let text as String: self = .string(text)
        case let data as Data: self = .data(data)
        case let date as Date: self = .date(date)
        case let array as [Any]: self = .array(array.compactMap { LegacyValue(propertyList: $0) })
        case let dictionary as [String: Any]: self = .dictionary(dictionary.compactMapValues { LegacyValue(propertyList: $0) })
        default:
            // Booleans and numbers are both `NSNumber` on Darwin: `objCType` tells them apart (LOT-060).
            guard let number = value as? NSNumber else { return nil }
            switch String(cString: number.objCType) {
            case "c", "B": self = .bool(number.boolValue)
            case "d", "f": self = .real(number.doubleValue)
            default: self = .integer(number.intValue)
            }
        }
    }

    /// Reads a plist document (XML or binary) as legacy `dictionaryWithContentsOfFile:` / `arrayWithContentsOfFile:` did.
    static func parse(_ data: Data) -> LegacyValue? {
        guard let object = try? PropertyListSerialization.propertyList(from: data, format: nil) else { return nil }
        return LegacyValue(propertyList: object)
    }

    /// The value as `NSNumber.intValue` read it (legacy `Favorites.swift:137-146`): numbers, booleans, numeric strings.
    var legacyInteger: Int? {
        switch self {
        case .integer(let value): value
        case .bool(let value): value ? 1 : 0
        case .real(let value): value.isFinite && abs(value) < 9.0e18 ? Int(value) : nil
        case .string(let text): Int(text)
        default: nil
        }
    }
}

/// The legacy app's `UserDefaults` standard suite, read only.
public protocol LegacyDefaults: Sendable {
    /// The stored value of `key`, or nil when absent or of a type no legacy key used.
    func value(forKey key: String) -> LegacyValue?
}

/// `LegacyDefaults` over a `UserDefaults` suite (the standard one is what the legacy app wrote, Q-1).
public struct UserDefaultsLegacyDefaults: LegacyDefaults, @unchecked Sendable {
    // UserDefaults is documented as thread-safe; this view never writes.
    private let defaults: UserDefaults

    /// Creates a read-only view of `defaults`.
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func value(forKey key: String) -> LegacyValue? {
        defaults.object(forKey: key).flatMap { LegacyValue(propertyList: $0) }
    }
}

/// `LegacyDefaults` over fixed values, for tests and previews.
public struct InMemoryLegacyDefaults: LegacyDefaults {
    private let values: [String: LegacyValue]

    /// Creates defaults holding `values`.
    public init(_ values: [String: LegacyValue] = [:]) {
        self.values = values
    }

    /// Creates defaults from a `defaults export` plist; empty when it is not a dictionary.
    public init(plist data: Data) {
        if case .dictionary(let values) = LegacyValue.parse(data) {
            self.values = values
        } else {
            self.values = [:]
        }
    }

    public func value(forKey key: String) -> LegacyValue? {
        values[key]
    }
}
