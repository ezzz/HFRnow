import Foundation
/// Text decoded from a response body, with how it was decoded.
public struct DecodedText: Sendable, Equatable {
    /// How the bytes were interpreted.
    public enum Encoding: Sendable, Equatable {
        /// Valid UTF-8.
        case utf8
        /// Invalid UTF-8 that also holds valid multi-byte text: bad sequences became U+FFFD.
        case utf8Lossy
        /// Windows-1252 (also used for declared ISO-8859-1, as browsers do).
        case windows1252
    }

    /// The decoded string.
    public let text: String
    /// The interpretation that produced `text`.
    public let encoding: Encoding

    /// Creates a decoded text.
    public init(text: String, encoding: Encoding) {
        self.text = text
        self.encoding = encoding
    }
}

/// Charset detection and tolerant decoding of HFR response bodies (UTF-8 confirmed for topic pages).
public enum TextDecoding {
    /// Decodes `data` using the `Content-Type` charset, then a `<meta>` hint, then UTF-8 with fallbacks. Never fails.
    public static func decode(_ data: Data, contentType: String?) -> DecodedText {
        let label = contentType.flatMap(charset(fromContentType:)) ?? sniffMetaCharset(in: data)
        if let label, isLegacySingleByte(label) { return decodeWindows1252(data) }
        // Declared UTF-8, or no usable declaration: UTF-8 first.
        let payload = data.starts(with: [0xEF, 0xBB, 0xBF]) ? data.dropFirst(3) : data[...]
        if let valid = String(validating: payload, as: UTF8.self) {
            return DecodedText(text: valid, encoding: .utf8)
        }
        // Invalid UTF-8: a page with a few stray bytes stays UTF-8; a page without any valid
        // multi-byte sequence is most likely a legacy single-byte page.
        // Lossy decoding is the point here: bad bytes become U+FFFD instead of failing.
        let lossy = String(decoding: payload, as: UTF8.self)  // swiftlint:disable:this optional_data_string_conversion
        let hasValidMultiByte = lossy.unicodeScalars.contains { $0.value > 0x7F && $0 != "\u{FFFD}" }
        return hasValidMultiByte ? DecodedText(text: lossy, encoding: .utf8Lossy) : decodeWindows1252(data)
    }

    /// The `charset` parameter of a `Content-Type` value, lowercased and unquoted.
    public static func charset(fromContentType value: String) -> String? {
        for parameter in value.split(separator: ";").dropFirst() {
            let parts = parameter.split(separator: "=", maxSplits: 1)
            guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "charset" else { continue }
            let quotes = CharacterSet(charactersIn: "\"'")
            let label = parts[1].trimmingCharacters(in: .whitespaces).trimmingCharacters(in: quotes)
            return label.isEmpty ? nil : label.lowercased()
        }
        return nil
    }

    /// The charset declared by a `<meta>` tag in the first 2 KiB, lowercased.
    public static func sniffMetaCharset(in data: Data) -> String? {
        let ascii = data.prefix(2048).map { $0 < 0x80 ? $0 : UInt8(ascii: "?") }
        let prefix = String(bytes: ascii, encoding: .utf8) ?? ""
        let pattern = /<meta[^>]*?charset\s*=\s*["']?\s*([A-Za-z0-9_:.\-]+)/.ignoresCase()
        return prefix.firstMatch(of: pattern).map { String($0.1).lowercased() }
    }

    private static func isLegacySingleByte(_ label: String) -> Bool {
        ["iso-8859-1", "iso8859-1", "latin1", "latin-1", "l1", "windows-1252", "cp1252", "us-ascii", "ascii"].contains(label)
    }

    private static let windows1252High: [UInt32] = [
        0x20AC, 0x0081, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, 0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x008D, 0x017D, 0x008F,
        0x0090, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, 0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x009D, 0x017E, 0x0178
    ]

    private static func decodeWindows1252(_ data: Data) -> DecodedText {
        var scalars = String.UnicodeScalarView()
        for byte in data {
            let value = (0x80...0x9F).contains(byte) ? windows1252High[Int(byte) - 0x80] : UInt32(byte)
            if let scalar = Unicode.Scalar(value) { scalars.append(scalar) }
        }
        return DecodedText(text: String(scalars), encoding: .windows1252)
    }
}
