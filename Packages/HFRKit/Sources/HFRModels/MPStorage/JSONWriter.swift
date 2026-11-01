/// Writes a `JSONValue` as compact JSON text, byte for byte what `JSONEncoder` writes with `.sortedKeys` and
/// `.withoutEscapingSlashes` (probed on Foundation, LOT-073 spec), except that numbers keep their exact text:
/// - object keys sorted by their UTF-8 bytes;
/// - in strings, `"` and `\` escaped, `\b`, `\t`, `\n`, `\f`, `\r` for those controls and `\u00xx` (lowercase hex) for the
///   other characters below U+0020; everything else as is (`/`, DEL, U+2028, non-ASCII);
/// - numbers as their lexeme, `true`, `false`, `null`.
enum JSONWriter {
    /// The text of `value`.
    static func write(_ value: JSONValue) -> String {
        var output: [UInt8] = []
        append(value, to: &output)
        return String(decoding: output, as: UTF8.self)
    }

    private static func append(_ value: JSONValue, to output: inout [UInt8]) {
        switch value {
        case .null:
            output.append(contentsOf: Array("null".utf8))
        case .bool(let flag):
            output.append(contentsOf: Array((flag ? "true" : "false").utf8))
        case .number(let number):
            output.append(contentsOf: Array(number.lexeme.utf8))
        case .string(let text):
            appendString(text, to: &output)
        case .array(let items):
            output.append(0x5B)
            for (index, item) in items.enumerated() {
                if index > 0 { output.append(0x2C) }
                append(item, to: &output)
            }
            output.append(0x5D)
        case .object(let members):
            output.append(0x7B)
            for (index, member) in members.sorted(by: { $0.key.utf8.lexicographicallyPrecedes($1.key.utf8) }).enumerated() {
                if index > 0 { output.append(0x2C) }
                appendString(member.key, to: &output)
                output.append(0x3A)
                append(member.value, to: &output)
            }
            output.append(0x7D)
        }
    }

    private static func appendString(_ text: String, to output: inout [UInt8]) {
        output.append(0x22)
        for byte in text.utf8 {
            if let letter = shortEscapes[byte] {
                output.append(contentsOf: [0x5C, letter])
            } else if byte < 0x20 {
                output.append(contentsOf: [0x5C, 0x75, 0x30, 0x30, hexDigits[Int(byte >> 4)], hexDigits[Int(byte & 0x0F)]])
            } else {
                output.append(byte)
            }
        }
        output.append(0x22)
    }

    /// `"`, `\` and the five controls `JSONEncoder` writes as a backslash and a letter.
    private static let shortEscapes: [UInt8: UInt8] = [0x22: 0x22, 0x5C: 0x5C, 0x08: 0x62, 0x09: 0x74, 0x0A: 0x6E, 0x0C: 0x66, 0x0D: 0x72]
    private static let hexDigits = Array("0123456789abcdef".utf8)
}
