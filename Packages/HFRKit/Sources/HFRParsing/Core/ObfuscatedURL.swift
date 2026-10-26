import Foundation

/// Decoder for the links HFR hides in a CSS class instead of an `href` (HFR-PROTOCOL §4).
///
/// The payload is the URL's UTF-8 bytes, two characters per byte, each character being the index of a nibble
/// (high first) in the alphabet `0A12B34C56D78E9F` (`RangeOfCharacters.m:92-138`; HFR's own `common.js`).
public enum ObfuscatedURL {
    /// Nibble alphabet: the character at index `n` encodes the value `n`.
    static let alphabet = Array("0A12B34C56D78E9F".utf8)

    /// Decodes a `class` attribute holding an obfuscated link, or returns nil.
    ///
    /// The attribute may hold other class tokens, split on ASCII whitespace as HTML does. Decoding happens
    /// only when a token starts with one of the three prefixes and is longer than it, and the attribute contains neither `/` nor `http`
    /// (a link in clear: `ObjCMessageActionsBuilder.m:80-89`). A payload of odd length, with a character
    /// outside the alphabet or that is not UTF-8 gives nil.
    public static func decode(classAttribute: String) -> String? {
        guard !isClearLink(classAttribute) else { return nil }
        for token in classAttribute.htmlClassTokens {
            guard let prefix = prefix(of: token) else { continue }
            return decode(payload: token.dropFirst(prefix.rawValue.count))
        }
        return nil
    }

    /// Absolute URL for a raw action value: decoded when obfuscated, used as is when it is a link in clear.
    ///
    /// A value carrying a prefix that fails to decode (or also holds `/` or `http`) gives nil rather than
    /// a URL built from the class name, which is what legacy code did (`ObjCMessageActionsBuilder.m:85-88`).
    public static func resolvedURL(from raw: String) -> URL? {
        let trimmed = String(raw.trimmingHTMLWhitespace)
        // Any value naming a prefix is meant to be obfuscated, even when the prefix is not at a token start.
        let marked = ObfuscatedURLPrefix.allCases.contains { trimmed.contains($0.rawValue) }
        if marked {
            return decode(classAttribute: trimmed).flatMap { HFRURL.absolute($0) }
        }
        return HFRURL.absolute(trimmed)
    }

    /// Encodes a URL with `prefix`: the inverse of `decode(classAttribute:)`, for tests and fixture anonymization.
    public static func encode(_ url: String, prefix: ObfuscatedURLPrefix) -> String {
        var token = prefix.rawValue.unicodeScalars
        for byte in url.utf8 {
            token.append(Unicode.Scalar(alphabet[Int(byte >> 4)]))
            token.append(Unicode.Scalar(alphabet[Int(byte & 0x0F)]))
        }
        return String(token)
    }

    // MARK: - Implementation

    /// Decodes a bare payload (the part after the prefix).
    static func decode(payload: Substring) -> String? {
        let characters = Array(payload.utf8)
        guard !characters.isEmpty, characters.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(characters.count / 2)
        var index = 0
        while index < characters.count {
            guard
                let high = alphabet.firstIndex(of: characters[index]),
                let low = alphabet.firstIndex(of: characters[index + 1])
            else { return nil }
            bytes.append(UInt8(high << 4 | low))
            index += 2
        }
        return String(validating: bytes, as: UTF8.self)
    }

    /// The prefix a class token starts with, when the token also carries a payload.
    private static func prefix(of token: Substring) -> ObfuscatedURLPrefix? {
        // `allCases` lists the longest prefix first; none is a prefix of another, so order is not load-bearing.
        ObfuscatedURLPrefix.allCases.first { token.hasPrefix($0.rawValue) && token.count > $0.rawValue.count }
    }

    /// A value with `/` or `http` is a link in clear: the alphabet has neither character.
    private static func isClearLink(_ value: String) -> Bool {
        value.contains("/") || value.lowercased().contains("http")
    }
}
