/// The one rule by which HFRStorage compares pseudos: blocklist and allowlist entries, draft recipients, accounts
/// (LOT-072).
///
/// Two pseudos designate the same member when their comparison forms are equal: every Unicode format character
/// removed (category Cf: U+200B, which HFR inserts to prevent impersonation and the MPStorage list stores raw, audit
/// E §7.5; U+FEFF and U+2060, which copy-paste and some keyboards insert), surrounding white space trimmed, then
/// lower-cased. `String` equality is canonical, so a composed and a decomposed accent are equal; diacritics stay
/// significant (`Élodie` is not `Elodie`). Legacy `findIndexFor:` (`BlackList.m:130-143`) removed U+200B and
/// lower-cased only.
///
/// Stored keys are not built here: an account's lists and drafts are keyed by the frozen account key (`AccountKey`,
/// ADR 0013 §7), which equals the comparison form of every `cleaned` pseudo, so of every pseudo `AccountBook` stores.
public enum PseudoNormalizer {
    /// The pseudo without format characters and surrounding white space; case kept (`AccountBook` stores it so).
    public static func cleaned(_ pseudo: String) -> String {
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: pseudo.unicodeScalars.filter { $0.properties.generalCategory != .format })
        return String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The comparison form of a pseudo: `cleaned`, then lower-cased.
    public static func comparisonForm(_ pseudo: String) -> String {
        cleaned(pseudo).lowercased()
    }

    /// Whether two pseudos designate the same member.
    public static func matches(_ lhs: String, _ rhs: String) -> Bool {
        comparisonForm(lhs) == comparisonForm(rhs)
    }
}
