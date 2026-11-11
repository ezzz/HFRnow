/// The account key of ADR 0013 §7: the `md_user` pseudo with every U+200B removed, then lower-cased, nothing else.
///
/// Frozen on purpose: the per-account documents of LOT-064, LOT-172's iCloud keys after them, and the blocklists and
/// drafts (LOT-072) are keyed by it, so a change would re-key stored data. Pseudos are compared by `PseudoNormalizer`.
/// Public so the app can tell which stored keys belong to no stored account (LOT-157).
public enum AccountKey {
    /// The account key of `pseudo`.
    public static func make(_ pseudo: String) -> String {
        String(String.UnicodeScalarView(pseudo.unicodeScalars.filter { $0 != "\u{200B}" })).lowercased()
    }

    /// The account key of `pseudo` for a write; an empty key is refused.
    static func forWriting(_ pseudo: String) throws(SmallStoreError) -> String {
        let key = make(pseudo)
        guard !key.isEmpty else { throw .emptyAccount }
        return key
    }
}
