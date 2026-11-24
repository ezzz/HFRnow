import Foundation

/// Small text rules shared by parsers.
public enum HFRText {
    /// First run of ASCII digits in `text` as an integer; nil when there is none or it overflows `Int`.
    ///
    /// Replaces the three legacy MP badge readers (`ObjCForumsParser.m:519-521`, `ObjCTopicListParser.m:88-92`,
    /// `MPBackgroundService.swift:113-139`), whose regex `[^.0-9]+([0-9]{1,})[^.0-9]+` needed text on both sides.
    public static func firstInteger(in text: String) -> Int? {
        guard let match = text.firstMatch(of: digitsPattern) else { return nil }
        return Int(match.output)
    }

    // `Regex` is not `Sendable` (its output type could hold non-Sendable captures). These literals capture
    // only `Substring`s and the compiled program is initialised atomically by the runtime, so sharing is safe.
    nonisolated(unsafe) private static let digitsPattern = /[0-9]+/

    /// Removes the zero-width spaces (U+200B) HFR injects into long pseudos (user feedback §4) and trims whitespace,
    /// as legacy code does before storing or comparing a pseudo (`MPStorage.m:626`, `Common.swift:1051-1055`).
    public static func normalizedPseudo(_ pseudo: String) -> String {
        let scalars = pseudo.unicodeScalars.filter { $0 != "\u{200B}" }
        return String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `key` (an account key, the URL-encoded `md_user` value, HFR-PROTOCOL §5, `W03`) as stored and percent-decoded, so it can be
    /// compared with the pseudo a page prints. `+` is read as a space as a tolerance (no capture shows it in `md_user`). A key that
    /// does not decode as UTF-8 stays raw only: how HFR encodes an accented pseudo is not captured (#140).
    public static func accountKeyForms(of key: String) -> [String] {
        let decoded = key.replacing("+", with: " ").removingPercentEncoding
        return decoded.map { $0 == key ? [key] : [key, $0] } ?? [key]
    }

    /// Key to compare two pseudos: normalized and lowercased (`BlackList.m:130-141`).
    public static func pseudoComparisonKey(_ pseudo: String) -> String {
        normalizedPseudo(pseudo).lowercased()
    }
}
