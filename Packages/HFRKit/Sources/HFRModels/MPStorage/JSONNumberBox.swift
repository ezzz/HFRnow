import Foundation

/// Carries exact number lexemes through `JSONDecoder` / `JSONEncoder`, which only know `Int64` and `Double`.
/// `MPStorageCodec` rewrites every number token of the text into a string `"<marker><lexeme>"` before decoding,
/// and rewrites those strings back into bare numbers after encoding. The marker is two private-use characters
/// (inside the BMP, so the non-BMP guard is unaffected); a real string starting with them is not expected.
enum JSONNumberBox {
    /// Prefix of a boxed number.
    static let marker = "\u{E000}\u{E001}"
    // swiftlint:disable:next force_unwrapping
    static let userInfoKey = CodingUserInfoKey(rawValue: "hfr.mpstorage.exactNumbers")! // Encoder flag; constant key, never nil

    /// The boxed form of a number.
    static func box(_ number: JSONNumber) -> String { marker + number.lexeme }

    /// The number a boxed string carries, or nil for an ordinary string.
    static func unbox(_ text: String) -> JSONNumber? {
        guard text.hasPrefix(marker) else { return nil }
        return JSONNumber(lexeme: String(text.dropFirst(marker.count)))
    }

    /// The lexeme of a boxed string, for the lenient readers of modelled fields.
    static func lexeme(_ text: String) -> String? { unbox(text)?.lexeme }

    /// Boxes every number token outside strings. Also refuses a `\u` escape of an unpaired UTF-16 surrogate,
    /// which Foundation would otherwise report as a type mismatch on the whole document.
    static func boxNumbers(in text: String) throws -> Data {
        let bytes = Array(text.utf8)
        var output: [UInt8] = []
        output.reserveCapacity(bytes.count + bytes.count / 4)
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            if byte == quote {
                let end = try endOfString(in: bytes, from: index)
                output.append(contentsOf: bytes[index..<end])
                index = end
            } else if byte == minus || isDigit(byte) {
                var end = index
                while end < bytes.count, isNumberByte(bytes[end]) { end += 1 }
                let token = String(bytes: bytes[index..<end], encoding: .utf8) ?? ""
                if let number = JSONNumber(lexeme: token) {
                    output.append(quote)
                    output.append(contentsOf: Array(box(number).utf8))
                    output.append(quote)
                } else {
                    output.append(contentsOf: bytes[index..<end])
                }
                index = end
            } else {
                output.append(byte)
                index += 1
            }
        }
        return Data(output)
    }

    /// Turns boxed numbers of encoder output back into bare number tokens (only whole strings are replaced).
    static func unboxNumbers(in text: String) throws -> String {
        let bytes = Array(text.utf8)
        var output: [UInt8] = []
        output.reserveCapacity(bytes.count)
        var index = 0
        while index < bytes.count {
            guard bytes[index] == quote else {
                output.append(bytes[index])
                index += 1
                continue
            }
            let end = try endOfString(in: bytes, from: index)
            let content = String(bytes: bytes[(index + 1)..<max(index + 1, end - 1)], encoding: .utf8) ?? ""
            if let number = unbox(content) {
                output.append(contentsOf: Array(number.lexeme.utf8))
            } else {
                output.append(contentsOf: bytes[index..<end])
            }
            index = end
        }
        guard let result = String(bytes: output, encoding: .utf8) else {
            throw EncodingError.invalidValue(text, .init(codingPath: [], debugDescription: "Not UTF-8"))
        }
        return result
    }

    private static let quote: UInt8 = 0x22
    private static let backslash: UInt8 = 0x5C
    private static let minus: UInt8 = 0x2D

    private static func isDigit(_ byte: UInt8) -> Bool { byte >= 0x30 && byte <= 0x39 }

    private static func isNumberByte(_ byte: UInt8) -> Bool {
        isDigit(byte) || byte == minus || byte == 0x2B || byte == 0x2E || byte == 0x65 || byte == 0x45
    }

    /// Index just past the closing quote of the string starting at `start` (or the end of the text).
    private static func endOfString(in bytes: [UInt8], from start: Int) throws -> Int {
        var index = start + 1
        while index < bytes.count {
            switch bytes[index] {
            case quote:
                return index + 1
            case backslash:
                index += try escapeLength(in: bytes, at: index)
            default:
                index += 1
            }
        }
        // A lone trailing backslash counts two bytes: clamp so a truncated text throws instead of trapping.
        return min(index, bytes.count)
    }

    /// Length of the escape at `index`; throws on an unpaired surrogate.
    private static func escapeLength(in bytes: [UInt8], at index: Int) throws -> Int {
        guard index + 1 < bytes.count, bytes[index + 1] == 0x75, let unit = hexUnit(in: bytes, at: index + 2) else {
            return 2
        }
        switch unit {
        case 0xD800...0xDBFF:
            guard index + 7 < bytes.count, bytes[index + 6] == backslash, bytes[index + 7] == 0x75,
                  let low = hexUnit(in: bytes, at: index + 8), (0xDC00...0xDFFF).contains(low) else {
                throw MPStorageError.unpairedSurrogate(byteOffset: index)
            }
            return 12
        case 0xDC00...0xDFFF:
            throw MPStorageError.unpairedSurrogate(byteOffset: index)
        default:
            return 6
        }
    }

    private static func hexUnit(in bytes: [UInt8], at index: Int) -> UInt16? {
        guard index + 4 <= bytes.count else { return nil }
        return String(bytes: bytes[index..<index + 4], encoding: .utf8).flatMap { UInt16($0, radix: 16) }
    }
}
