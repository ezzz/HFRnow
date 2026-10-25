import Foundation
/// An ordered `application/x-www-form-urlencoded` body, always UTF-8 and correctly percent-encoded.
///
/// Fixes the legacy bug where accents were left unencoded (`alphanumericCharacterSet` includes Unicode letters).
public struct FormBody: Sendable, Equatable {
    /// One name/value pair.
    public struct Field: Sendable, Equatable {
        /// Field name.
        public var name: String
        /// Field value (unencoded).
        public var value: String

        /// Creates a field.
        public init(name: String, value: String) {
            self.name = name
            self.value = value
        }
    }

    /// How line breaks in names and values are written.
    public enum Newlines: Sendable, Equatable {
        /// Bytes as given (legacy and redface2 behaviour).
        case preserve
        /// Every CR, LF or CRLF becomes CRLF, as a browser submitting the site's textarea does.
        case crlf
    }

    /// Content type to send with `data`.
    public static let contentType = "application/x-www-form-urlencoded; charset=utf-8"

    /// Fields in submission order (the server-side search expects an exact order).
    public private(set) var fields: [Field]
    /// Line-break handling; whether HFR needs CRLF is still open (HFR-PROTOCOL §7, X11).
    public var newlines: Newlines

    /// Creates a body from ordered pairs.
    public init(_ fields: [(name: String, value: String)] = [], newlines: Newlines = .preserve) {
        self.fields = fields.map { Field(name: $0.name, value: $0.value) }
        self.newlines = newlines
    }

    /// Appends a field after the existing ones.
    public mutating func append(_ name: String, _ value: String) {
        fields.append(Field(name: name, value: value))
    }

    /// The encoded body, for example `a=%C3%A9&b=x+y`.
    public var encodedString: String {
        fields
            .map { Self.encode($0.name, newlines: newlines) + "=" + Self.encode($0.value, newlines: newlines) }
            .joined(separator: "&")
    }

    /// The encoded body as bytes.
    public var data: Data { Data(encodedString.utf8) }

    /// Percent-encodes one component: `A-Za-z0-9*-._` stay, space becomes `+`, all other UTF-8 bytes become `%XX`.
    static func encode(_ text: String, newlines: Newlines) -> String {
        let hex = Array("0123456789ABCDEF".utf8)
        var output: [UInt8] = []
        func percent(_ byte: UInt8) {
            output.append(UInt8(ascii: "%"))
            output.append(hex[Int(byte >> 4)])
            output.append(hex[Int(byte & 0x0F)])
        }
        let bytes = Array(text.utf8)
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            switch byte {
            case UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "a")...UInt8(ascii: "z"),
                 UInt8(ascii: "0")...UInt8(ascii: "9"),
                 UInt8(ascii: "*"), UInt8(ascii: "-"), UInt8(ascii: "."), UInt8(ascii: "_"):
                output.append(byte)
            case UInt8(ascii: " "):
                output.append(UInt8(ascii: "+"))
            case 13 where newlines == .crlf:
                if index < bytes.count, bytes[index] == 10 { index += 1 }
                percent(13)
                percent(10)
            case 10 where newlines == .crlf:
                percent(13)
                percent(10)
            default:
                percent(byte)
            }
        }
        // Output is pure ASCII by construction, so the failable conversion never returns nil.
        return String(bytes: output, encoding: .utf8) ?? ""
    }
}
