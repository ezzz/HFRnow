import Foundation

/// Percent-encoding for URL query values (not form bodies: those use `FormBody`).
enum QueryEncoding {
    /// Encodes `text` as UTF-8: unreserved characters (`A-Za-z0-9-._~`) stay, every other byte becomes `%XX` in uppercase.
    ///
    /// A space is `%20` and `+` is `%2B`, as the legacy smiley search wrote them (`SmileySearchService.swift:36-40`).
    /// `extraLiterals` lists ASCII characters that must stay as they are (for example `/` in a REST path).
    static func encode(_ text: String, extraLiterals: Set<UInt8> = []) -> String {
        let hex = Array("0123456789ABCDEF".utf8)
        var output: [UInt8] = []
        for byte in text.utf8 {
            switch byte {
            case UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "a")...UInt8(ascii: "z"),
                 UInt8(ascii: "0")...UInt8(ascii: "9"),
                 UInt8(ascii: "-"), UInt8(ascii: "."), UInt8(ascii: "_"), UInt8(ascii: "~"):
                output.append(byte)
            case _ where extraLiterals.contains(byte):
                output.append(byte)
            default:
                output.append(UInt8(ascii: "%"))
                output.append(hex[Int(byte >> 4)])
                output.append(hex[Int(byte & 0x0F)])
            }
        }
        // Output is pure ASCII by construction, so the failable conversion never returns nil.
        return String(bytes: output, encoding: .utf8) ?? ""
    }
}
