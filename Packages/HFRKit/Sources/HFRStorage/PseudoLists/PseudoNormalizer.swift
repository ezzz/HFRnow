/// Matching rules for pseudos, carried over from the legacy `findIndexFor:` (`BlackList.m:130-143`).
///
/// HFR pseudos are compared case-insensitively and without zero-width spaces (U+200B), which the forum
/// inserts to prevent impersonation and which the server-side MPStorage list stores raw (audit E §7.5).
public enum PseudoNormalizer {
    private static let zeroWidthSpace: Character = "\u{200B}"

    /// The comparison form of a pseudo: zero-width spaces removed, then lower-cased.
    public static func normalize(_ pseudo: String) -> String {
        pseudo.filter { $0 != zeroWidthSpace }.lowercased()
    }

    /// Whether two pseudos designate the same member.
    public static func matches(_ lhs: String, _ rhs: String) -> Bool {
        normalize(lhs) == normalize(rhs)
    }
}
