import HFRModels
import HFRParsing

/// Which messages of a topic the post filter keeps (legacy "Filtrer les posts", `ParseMessagesOperation.m:176-347`).
///
/// A message is kept when any rule holds:
/// - it was quoted at least `minimumQuoteCount` times (HFR's own "Message cité N fois" trailer, `quotedByCount`);
/// - its author is the account's `pseudo`;
/// - one of its quotes, at any depth, cites `pseudo` (LOT-032 authors, legacy rule `:198-206`);
/// - its content mentions `pseudo`, as text anywhere in the content HTML, case-insensitive (`:327-331`);
/// - `includesWhitelist` is on and its author is in `whitelist` (`:183-186`).
/// Pseudos compare like `HFRText.pseudoComparisonKey` (zero-width spaces removed, trimmed, lower-cased).
public struct FilteredPostsCriteria: Sendable, Hashable {
    /// Legacy's default and floor: a stored value of 0 or less reads as 3 (`ParseMessagesOperation.m:340-343`).
    public static let defaultMinimumQuoteCount = 3

    /// How many times a message must have been quoted to be kept; 0 or less means the default, 3.
    public var minimumQuoteCount: Int
    /// The account's pseudo; nil (or blank) turns off the rules about the account (own posts, quotes, mentions).
    public var pseudo: String?
    /// Pseudos whose messages are kept when `includesWhitelist` is on (the app's whitelist).
    public var whitelist: [String]
    /// Keeps the messages of whitelisted authors (legacy setting `filter_posts_quotes` containing `wl`, on by default).
    public var includesWhitelist: Bool

    /// Creates criteria; the defaults are legacy's (`HFRplusAppDelegate.m:108-114`).
    public init(
        minimumQuoteCount: Int = defaultMinimumQuoteCount, pseudo: String? = nil, whitelist: [String] = [],
        includesWhitelist: Bool = true
    ) {
        self.minimumQuoteCount = minimumQuoteCount
        self.pseudo = pseudo
        self.whitelist = whitelist
        self.includesWhitelist = includesWhitelist
    }

    /// The quote count actually required.
    public var effectiveMinimumQuoteCount: Int {
        minimumQuoteCount > 0 ? minimumQuoteCount : Self.defaultMinimumQuoteCount
    }

    /// True when `block`, whose quotes are `quotes`, is kept.
    public func keeps(_ block: MessageBlock, quotes: [MessageQuote]) -> Bool {
        if let count = block.quotedByCount, count >= effectiveMinimumQuoteCount { return true }
        let author = HFRText.pseudoComparisonKey(block.author)
        if includesWhitelist, whitelist.contains(where: { HFRText.pseudoComparisonKey($0) == author }) { return true }
        let own = HFRText.pseudoComparisonKey(pseudo ?? "")
        guard !own.isEmpty else { return false }
        if author == own { return true }
        if quotes.contains(where: { $0.author.map(HFRText.pseudoComparisonKey) == own }) { return true }
        return block.contentHTML.lowercased().contains(own)
    }
}
