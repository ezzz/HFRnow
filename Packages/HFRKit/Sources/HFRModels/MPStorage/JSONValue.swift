/// Any JSON value, used to keep parts of the MPStorage document this app does not model (other clients write them).
/// Numbers keep their exact text when the document goes through `MPStorageCodec`; a plain `JSONDecoder` /
/// `JSONEncoder` round trip goes through `Int64` or `Double` instead.
public enum JSONValue: Sendable, Hashable, Codable {
    /// `null`.
    case null
    /// `true` / `false`.
    case bool(Bool)
    /// Any number, as written.
    case number(JSONNumber)
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
        } else if let value = try? container.decode(Int64.self) {
            self = .number(JSONNumber(value))
        } else if let value = try? container.decode(Double.self) {
            self = .number(JSONNumber(value))
        } else if let value = try? container.decode(String.self) {
            self = JSONNumberBox.unbox(value).map(JSONValue.number) ?? .string(value)
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
        case .number(let value):
            guard JSONNumber.isValid(value.lexeme) else {
                // Only `JSONNumber(Double)` with a non-finite value can get here.
                throw EncodingError.invalidValue(value.lexeme, .init(codingPath: encoder.codingPath, debugDescription: "Not a JSON number"))
            }
            if encoder.userInfo[JSONNumberBox.userInfoKey] as? Bool == true {
                try container.encode(JSONNumberBox.box(value))
            } else if let integer = value.int64Value {
                try container.encode(integer)
            } else {
                try container.encode(value.doubleValue ?? 0)
            }
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}
