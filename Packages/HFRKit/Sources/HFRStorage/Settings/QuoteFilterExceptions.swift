/// The `filter_posts_quotes` setting: what keeps a post visible when "only posts that quote me" filtering is on.
///
/// Stored as a free string; legacy readers test `containsString:@"wl"` and `containsString:@"pseudo"`
/// (`ParseMessagesOperation.m:187,320,327`), so those substring rules are kept.
public struct QuoteFilterExceptions: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    /// Creates the set from its bits.
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// Posts by allowlisted authors stay visible (stored token `wl`).
    public static let allowlistedAuthors = QuoteFilterExceptions(rawValue: 1 << 0)
    /// Posts that mention the reader's pseudo stay visible (stored token `pseudo`).
    public static let mentionsOwnPseudo = QuoteFilterExceptions(rawValue: 1 << 1)
    /// The legacy default, `wl_pseudo`.
    public static let standard: QuoteFilterExceptions = [.allowlistedAuthors, .mentionsOwnPseudo]

    /// Parses the stored string with the legacy substring rules.
    public init(storedString: String) {
        var result: QuoteFilterExceptions = []
        if storedString.contains("wl") { result.insert(.allowlistedAuthors) }
        if storedString.contains("pseudo") { result.insert(.mentionsOwnPseudo) }
        self = result
    }

    /// The string persisted: `wl_pseudo`, `pseudo`, `wl` or an empty string.
    public var storedString: String {
        switch (contains(.allowlistedAuthors), contains(.mentionsOwnPseudo)) {
        case (true, true): "wl_pseudo"
        case (false, true): "pseudo"
        case (true, false): "wl"
        case (false, false): ""
        }
    }
}
