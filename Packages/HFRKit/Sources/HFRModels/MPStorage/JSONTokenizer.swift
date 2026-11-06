/// Reads JSON text into a `JSONValue`, every number kept as its exact text (LOT-073), for `MPStorageCodec`.
///
/// RFC 8259, plus what Foundation's `JSONDecoder` also accepts, so a document it read still reads: a byte order mark
/// before the value, and a trailing comma before `]` or `}`. As in `JSONDecoder`, a repeated object key keeps its first
/// value, and nesting deeper than 512 arrays or objects is refused. A `\u` escape of an unpaired UTF-16 surrogate throws
/// `MPStorageError.unpairedSurrogate` at the escape's byte offset; any other malformed text throws
/// `DecodingError.dataCorrupted`.
enum JSONTokenizer {
    /// Deepest nesting read, as `JSONDecoder` (512 levels read, 513 refused). It also bounds the recursion: on a 512 KiB
    /// thread stack (a Swift Testing or concurrency thread) a debug build overflows at about 1 000 levels.
    static let maximumDepth = 512

    /// The value `text` holds.
    static func parse(_ text: String) throws -> JSONValue {
        var reader = Reader(bytes: Array(text.utf8))
        reader.skipByteOrderMark()
        reader.skipWhitespace()
        let value = try reader.value(depth: 1)
        reader.skipWhitespace()
        guard reader.isAtEnd else { throw reader.corrupted("Unexpected text after the value") }
        return value
    }

    private struct Reader {
        let bytes: [UInt8]
        var index = 0

        var isAtEnd: Bool { index >= bytes.count }
        private var current: UInt8? { index < bytes.count ? bytes[index] : nil }

        mutating func skipByteOrderMark() {
            if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { index = 3 }
        }

        mutating func skipWhitespace() {
            while let byte = current, byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D { index += 1 }
        }

        func corrupted(_ reason: String) -> DecodingError {
            DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "\(reason) at byte \(index)"))
        }

        mutating func value(depth: Int) throws -> JSONValue {
            switch current {
            case 0x7B?: return try object(depth: depth)
            case 0x5B?: return try array(depth: depth)
            case 0x22?: return .string(try string())
            case 0x74?: try literal("true"); return .bool(true)
            case 0x66?: try literal("false"); return .bool(false)
            case 0x6E?: try literal("null"); return .null
            case let byte? where byte == 0x2D || Self.isDigit(byte): return .number(try number())
            default: throw corrupted("Expected a value")
            }
        }

        private mutating func object(depth: Int) throws -> JSONValue {
            guard depth <= JSONTokenizer.maximumDepth else { throw corrupted("Too deeply nested") }
            index += 1
            var members: [String: JSONValue] = [:]
            skipWhitespace()
            if current == 0x7D { index += 1; return .object(members) }
            while true {
                guard current == 0x22 else { throw corrupted("Expected a key") }
                let key = try string()
                skipWhitespace()
                guard current == 0x3A else { throw corrupted("Expected ':'") }
                index += 1
                skipWhitespace()
                let member = try value(depth: depth + 1)
                // The first occurrence wins, as with `JSONDecoder`.
                if members[key] == nil { members[key] = member }
                guard try continues(closing: 0x7D) else { return .object(members) }
            }
        }

        private mutating func array(depth: Int) throws -> JSONValue {
            guard depth <= JSONTokenizer.maximumDepth else { throw corrupted("Too deeply nested") }
            index += 1
            var items: [JSONValue] = []
            skipWhitespace()
            if current == 0x5D { index += 1; return .array(items) }
            while true {
                items.append(try value(depth: depth + 1))
                guard try continues(closing: 0x5D) else { return .array(items) }
            }
        }

        /// After a member or an item: true when another one follows, false past the closing bracket (a trailing comma
        /// before it is accepted, as `JSONDecoder` does).
        private mutating func continues(closing: UInt8) throws -> Bool {
            skipWhitespace()
            if current == closing { index += 1; return false }
            guard current == 0x2C else { throw corrupted("Expected ',' or a closing bracket") }
            index += 1
            skipWhitespace()
            if current == closing { index += 1; return false }
            return true
        }

        private mutating func literal(_ word: String) throws {
            let expected = Array(word.utf8)
            guard bytes[index...].starts(with: expected) else { throw corrupted("Expected \(word)") }
            index += expected.count
        }

        /// `-? (0 | [1-9][0-9]*) (. [0-9]+)? ([eE] [+-]? [0-9]+)?`; what follows must be a delimiter, so `01` is refused there.
        private mutating func number() throws -> JSONNumber {
            let start = index
            if current == 0x2D { index += 1 }
            if current == 0x30 { index += 1 } else { try requireDigits() }
            if current == 0x2E {
                index += 1
                try requireDigits()
            }
            if current == 0x65 || current == 0x45 {
                index += 1
                if current == 0x2B || current == 0x2D { index += 1 }
                try requireDigits()
            }
            guard let lexeme = String(validating: bytes[start..<index], as: UTF8.self), let number = JSONNumber(lexeme: lexeme)
            else { throw corrupted("Malformed number") }
            return number
        }

        private mutating func requireDigits() throws {
            let start = index
            while let byte = current, Self.isDigit(byte) { index += 1 }
            guard index > start else { throw corrupted("Expected a digit") }
        }

        private mutating func string() throws -> String {
            index += 1
            var output: [UInt8] = []
            while true {
                guard let byte = current else { throw corrupted("Unterminated string") }
                switch byte {
                case 0x22:
                    index += 1
                    // The bytes come from a Swift string and from encoded scalars: always valid UTF-8.
                    guard let text = String(validating: output, as: UTF8.self) else { throw corrupted("Invalid UTF-8") }
                    return text
                case 0x5C:
                    try escape(into: &output)
                case 0x00..<0x20:
                    throw corrupted("Control character in a string")
                default:
                    output.append(byte)
                    index += 1
                }
            }
        }

        private mutating func escape(into output: inout [UInt8]) throws {
            let start = index
            guard index + 1 < bytes.count else { throw corrupted("Unterminated escape") }
            if let replacement = Self.simpleEscapes[bytes[index + 1]] {
                output.append(replacement)
                index += 2
                return
            }
            guard bytes[index + 1] == 0x75, let unit = hexUnit(at: index + 2) else { throw corrupted("Invalid escape") }
            index += 6
            var scalarValue = UInt32(unit)
            switch unit {
            case 0xD800...0xDBFF:
                guard index + 1 < bytes.count, bytes[index] == 0x5C, bytes[index + 1] == 0x75,
                      let low = hexUnit(at: index + 2), (0xDC00...0xDFFF).contains(low) else {
                    throw MPStorageError.unpairedSurrogate(byteOffset: start)
                }
                index += 6
                scalarValue = 0x10000 + ((UInt32(unit) - 0xD800) << 10) + (UInt32(low) - 0xDC00)
            case 0xDC00...0xDFFF:
                throw MPStorageError.unpairedSurrogate(byteOffset: start)
            default:
                break
            }
            guard let scalar = Unicode.Scalar(scalarValue) else { throw corrupted("Invalid escape") }
            UTF8.encode(scalar) { output.append($0) }
        }

        /// Four hexadecimal digits at `position`, nothing else (no sign).
        private func hexUnit(at position: Int) -> UInt16? {
            guard position + 4 <= bytes.count else { return nil }
            var unit: UInt16 = 0
            for byte in bytes[position..<position + 4] {
                let digit: UInt8
                switch byte {
                case 0x30...0x39: digit = byte - 0x30
                case 0x41...0x46: digit = byte - 0x41 + 10
                case 0x61...0x66: digit = byte - 0x61 + 10
                default: return nil
                }
                unit = unit << 4 | UInt16(digit)
            }
            return unit
        }

        /// `\"`, `\\`, `\/`, `\b`, `\f`, `\n`, `\r`, `\t` and the byte each stands for.
        private static let simpleEscapes: [UInt8: UInt8] = [
            0x22: 0x22, 0x5C: 0x5C, 0x2F: 0x2F, 0x62: 0x08, 0x66: 0x0C, 0x6E: 0x0A, 0x72: 0x0D, 0x74: 0x09
        ]

        private static func isDigit(_ byte: UInt8) -> Bool { byte >= 0x30 && byte <= 0x39 }
    }
}
