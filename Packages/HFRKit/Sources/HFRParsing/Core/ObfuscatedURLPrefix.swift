/// Class prefixes HFR uses to mark an obfuscated link; the hex payload follows directly, in the same class token.
///
/// `noClass` (20 characters) wraps message actions (quote, edit: `RangeOfCharacters.m:92-114`);
/// `plain` (12) is the list pager (`RangeOfCharacters.m:116-138`, `ObjCTopicListParser.m:192-245`);
/// `blank` (18) is reported by redface2 only (research §4.3 E7).
public enum ObfuscatedURLPrefix: String, Sendable, CaseIterable {
    /// `md_noclass_cryptlink`, 20 characters.
    case noClass = "md_noclass_cryptlink"
    /// `md_blank_cryptlink`, 18 characters.
    case blank = "md_blank_cryptlink"
    /// `md_cryptlink`, 12 characters.
    case plain = "md_cryptlink"
}
