import Foundation

/// A value of the iCloud key-value store: the four settings shapes, and data for JSON documents (LOT-172).
public enum SyncedValue: Sendable, Hashable, Codable {
    /// A boolean.
    case bool(Bool)
    /// An integer.
    case int(Int)
    /// A floating-point number.
    case double(Double)
    /// A string.
    case string(String)
    /// Bytes, for the list and position documents.
    case data(Data)

    /// The value of a setting.
    public init(_ raw: SettingRawValue) {
        switch raw {
        case .bool(let flag): self = .bool(flag)
        case .int(let number): self = .int(number)
        case .double(let number): self = .double(number)
        case .string(let text): self = .string(text)
        }
    }

    /// The setting shape of this value; nil for data, which no setting stores.
    public var settingRawValue: SettingRawValue? {
        switch self {
        case .bool(let flag): .bool(flag)
        case .int(let number): .int(number)
        case .double(let number): .double(number)
        case .string(let text): .string(text)
        case .data: nil
        }
    }
}
