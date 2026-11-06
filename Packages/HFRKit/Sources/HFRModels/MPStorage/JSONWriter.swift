/// Writes a `JSONValue` as compact JSON text, byte for byte what `JSONEncoder` writes with `.sortedKeys` and
/// `.withoutEscapingSlashes` (probed on Foundation, LOT-073 spec), except that numbers keep their exact text:
/// - object keys sorted by their UTF-8 bytes;
/// - in strings, `"` and `\` escaped, `\b`, `\t`, `\n`, `\f`, `\r` for those controls and `\u00xx` (lowercase hex) for the
///   other characters below U+0020; everything else as is (`/`, DEL, U+2028, non-ASCII);
/// - numbers as their lexeme, `true`, `false`, `null`.
enum JSONWriter {
    /// The text of `value`.
    static func write(_ value: JSONValue) -> String {
        var output = ""
        append(value, to: &output)
        return output
    }

    private static func append(_ value: JSONValue, to output: inout String) {
        switch value {
        case .null:
            output += "null"
        case .bool(let flag):
            output += flag ? "true" : "false"
        case .number(let number):
            output += number.lexeme
        case .string(let text):
            appendString(text, to: &output)
        case .array(let items):
            output += "["
            for (index, item) in items.enumerated() {
                if index > 0 { output += "," }
                append(item, to: &output)
            }
            output += "]"
        case .object(let members):
            output += "{"
            for (index, member) in members.sorted(by: { $0.key.utf8.lexicographicallyPrecedes($1.key.utf8) }).enumerated() {
                if index > 0 { output += "," }
                appendString(member.key, to: &output)
                output += ":"
                append(member.value, to: &output)
            }
            output += "}"
        }
    }

    /// The string's scalars as they are, apart from the escapes: no normalization, so the bytes are the string's own.
    private static func appendString(_ text: String, to output: inout String) {
        output += "\""
        for scalar in text.unicodeScalars {
            if let escape = shortEscapes[scalar] {
                output += escape
            } else if scalar.value < 0x20 {
                output += "\\u00" + String(hexDigits[Int(scalar.value >> 4)]) + String(hexDigits[Int(scalar.value & 0x0F)])
            } else {
                output.unicodeScalars.append(scalar)
            }
        }
        output += "\""
    }

    /// `"`, `\` and the five controls `JSONEncoder` writes as a backslash and a letter.
    private static let shortEscapes: [Unicode.Scalar: String] = [
        "\"": "\\\"", "\\": "\\\\", "\u{08}": "\\b", "\t": "\\t", "\n": "\\n", "\u{0C}": "\\f", "\r": "\\r"
    ]
    private static let hexDigits = Array("0123456789abcdef")
}
