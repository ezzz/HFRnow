/// Any JSON value, used to keep parts of the MPStorage document this app does not model (other clients write them).
/// Numbers are `Double`: integers above 2^53 lose precision.
public enum JSONValue: Sendable, Hashable, Codable {
    /// `null`.
    case null
    /// `true` / `false`.
    case bool(Bool)
    /// Any number.
    case number(Double)
    /// A string.
    case string(String)
    /// An array.
    case array([JSONValue])
    /// An object.
    case object([String: JSONValue])

    /// Decodes whatever JSON value is next.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    /// Encodes the value back as the same JSON.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}
