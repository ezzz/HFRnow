/// A JSON number kept as its exact text (`9007199254740993`, `1e17`, `-0.0`), so values written by other
/// clients are written back byte for byte. Equality is textual: `1` and `1.0` differ.
public struct JSONNumber: Sendable, Hashable, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral, CustomStringConvertible {
    /// The number as it appears in the JSON text.
    public let lexeme: String

    /// Wraps a lexeme; nil unless it is a valid JSON number.
    public init?(lexeme: String) {
        guard Self.isValid(lexeme) else { return nil }
        self.lexeme = lexeme
    }

    /// An integer.
    public init(_ value: Int64) { lexeme = String(value) }

    /// A double, written as Swift's shortest round-trip form (`1.5`, `1e+17`), whole values without `.0`.
    /// A non-finite value has no JSON form: encoding it throws.
    public init(_ value: Double) {
        var text = value.description
        if text.hasSuffix(".0") { text.removeLast(2) }
        lexeme = text
    }

    /// Integer literal.
    public init(integerLiteral value: Int64) { self.init(value) }

    /// Float literal.
    public init(floatLiteral value: Double) { self.init(value) }

    /// The value as a `Double` (may round).
    public var doubleValue: Double? { Double(lexeme) }

    /// The value as an `Int64`, when the lexeme is a plain integer in range.
    public var int64Value: Int64? { Int64(lexeme) }

    /// The lexeme.
    public var description: String { lexeme }

    /// RFC 8259 number grammar: `-? (0 | [1-9][0-9]*) (. [0-9]+)? ([eE] [+-]? [0-9]+)?`.
    static func isValid(_ text: String) -> Bool {
        var bytes = Array(text.utf8)[...]
        func digits() -> Int {
            let count = bytes.prefix { $0 >= 0x30 && $0 <= 0x39 }.count
            bytes = bytes.dropFirst(count)
            return count
        }
        if bytes.first == 0x2D { bytes = bytes.dropFirst() }
        if bytes.first == 0x30 {
            bytes = bytes.dropFirst()
        } else if digits() == 0 {
            return false
        }
        if bytes.first == 0x2E {
            bytes = bytes.dropFirst()
            guard digits() > 0 else { return false }
        }
        if bytes.first == 0x65 || bytes.first == 0x45 {
            bytes = bytes.dropFirst()
            if bytes.first == 0x2B || bytes.first == 0x2D { bytes = bytes.dropFirst() }
            guard digits() > 0 else { return false }
        }
        return bytes.isEmpty
    }
}
