import Foundation
import HFRModels
import HFRStorage

// Port of the visibility rules of HFRswift/Wrapped/LinkItem.m (toHTML:isMP:, :26-55, 80-93, 277-296) and
// HFRswift/Wrapped/ParseMessagesOperation.m:205-224 @ 2440d79, GAP-066.
// Differences: one pure policy instead of string replacement on a template (ADR 0006); pseudos compare with the store's
// rule (`PseudoNormalizer`, LOT-072); the author's own message is never collapsed; own highlights are off on private messages.
/// What the reader does with a message or a quote, from who wrote it: pure, so every case is tested without a web view.
///
/// Precedence is legacy's: a moderator message, then your own, then an allowlisted author (a blocklisted pseudo is never
/// allowlisted, `BlackList.m:119-122`), then a blocklisted one.
struct VisibilityPolicy: Equatable, Sendable {
    /// How a message is shown.
    enum Post: Equatable, Sendable {
        /// Written by the moderation (`message mode`, `LinkItem.m:45`).
        case moderation
        /// Written by the current account (`message me`, `LinkItem.m:47`, "Egopost").
        case own
        /// By an allowlisted author (`message whitelist`, `LinkItem.m:49`).
        case allowlisted
        /// By a blocklisted author: collapsed until the reader asks (`message bl`, `LinkItem.m:51`).
        case blocked
        /// Anything else.
        case normal
    }

    /// How a quote block is shown.
    enum Quote: Equatable, Sendable {
        /// Quotes the current account (`citation_me_quoted`, `ParseMessagesOperation.m:207`, "Egoquote").
        case ofMe
        /// Quotes an allowlisted author (`citation_whitelist`, `:209`).
        case allowlisted
        /// Quotes a blocklisted author: collapsed until the reader asks (`citation_blacklist`, `:211`).
        case blocked
        /// Anonymous quote or any other author.
        case normal
    }

    /// The moderation's author name, compared as legacy does (`LinkItem.m:44`).
    static let moderationName = "Modération"

    /// Show nothing about the author of a collapsed message and of a collapsed quote (`blacklist_hide_pseudo`,
    /// `LinkItem.m:81, 290`).
    var hidesBlockedPseudo: Bool
    private var ownKey: String?
    private var blockedKeys: Set<String>
    private var allowedKeys: Set<String>

    /// A policy over the account's `ownPseudo` and its lists; pseudos are compared by `PseudoNormalizer.comparisonForm`.
    init(ownPseudo: String? = nil, blocklist: [String] = [], allowlist: [String] = [], hidesBlockedPseudo: Bool = false) {
        let own = ownPseudo.map(PseudoNormalizer.comparisonForm)
        ownKey = own?.isEmpty == false ? own : nil
        blockedKeys = Set(blocklist.map(PseudoNormalizer.comparisonForm).filter { !$0.isEmpty })
        allowedKeys = Set(allowlist.map(PseudoNormalizer.comparisonForm).filter { !$0.isEmpty })
        self.hidesBlockedPseudo = hidesBlockedPseudo
    }

    /// No pseudo, no list: every message and quote is normal.
    static let none = VisibilityPolicy()

    /// Whether the policy can change how anything is shown.
    var isNeutral: Bool { ownKey == nil && blockedKeys.isEmpty && allowedKeys.isEmpty }

    /// The same lists without the highlights of the account's own messages and of quotes of it. Legacy states that "ego quote"
    /// is not applied on private messages (`MessagesTableViewController.m:1401`); its `isMP:` parameter is never read, so
    /// the intent is applied here (issue #208).
    func withoutOwnHighlights() -> VisibilityPolicy {
        var copy = self
        copy.ownKey = nil
        return copy
    }

    /// How a message by `author` is shown.
    func post(by author: String) -> Post {
        if author == Self.moderationName { return .moderation }
        let key = PseudoNormalizer.comparisonForm(author)
        if let ownKey, key == ownKey { return .own }
        if blockedKeys.contains(key) { return .blocked }
        if allowedKeys.contains(key) { return .allowlisted }
        return .normal
    }

    /// How a quote of `author` is shown; nil is an anonymous quote.
    func quote(by author: String?) -> Quote {
        guard let author else { return .normal }
        let key = PseudoNormalizer.comparisonForm(author)
        if let ownKey, key == ownKey { return .ofMe }
        if allowedKeys.contains(key), !blockedKeys.contains(key) { return .allowlisted }
        if blockedKeys.contains(key) { return .blocked }
        return .normal
    }
}

/// The two pseudo lists as the reader reads them (the account's blocklist, the global allowlist), in the store's entries'
/// spelling. Read from the store by `PseudoListsSnapshot`; the editors are LOT-118's.
struct PseudoLists: Equatable, Sendable {
    var blocklist: [String] = []
    var allowlist: [String] = []

    /// The allowlist without the pseudos that are blocklisted: legacy's `isWL:` refuses a blocklisted pseudo
    /// (`BlackList.m:119-122`); what the post filter's criteria take (`FilteredPostsCriteria.allowlist`).
    var allowlistWithoutBlocked: [String] {
        let blocked = Set(blocklist.map(PseudoNormalizer.comparisonForm))
        return allowlist.filter { !blocked.contains(PseudoNormalizer.comparisonForm($0)) }
    }
}

/// Adds the visibility class tokens to the quote tables of a message's content.
///
/// Works on the sanitized HTML of LOT-034 (SwiftSoup output: tags are well formed, text `<` is an entity) and on the typed
/// quotes of LOT-032, which list the same tables in the same document order. A count that differs leaves the content
/// untouched rather than classing the wrong table.
enum QuoteMarkup {
    private static let quoteClasses: Set<String> = ["citation", "oldcitation", "quote"]

    /// `html` with `quote-me`, `quote-allowed`, `quote-blocked` (and `quote-hide-author`) added to the class attribute of the
    /// quote table each entry of `quotes` stands for.
    static func annotate(_ html: String, quotes: [MessageQuote], policy: VisibilityPolicy) -> String {
        guard !quotes.isEmpty, !policy.isNeutral else { return html }
        let tokens = quotes.map { token(for: policy.quote(by: $0.author), hidesAuthor: policy.hidesBlockedPseudo) }
        guard tokens.contains(where: { $0 != nil }) else { return html }
        let bytes = Array(html.utf8)
        var insertions: [(offset: Int, text: String)] = []
        var index = 0
        var found = 0
        while let start = nextTable(in: bytes, from: index) {
            let end = endOfTag(in: bytes, from: start)
            index = end
            guard let value = classValue(in: bytes, tag: start..<end), isQuote(bytes[value]) else { continue }
            if found < tokens.count, let token = tokens[found] { insertions.append((value.upperBound, " " + token)) }
            found += 1
        }
        guard found == quotes.count else { return html }
        var result: [UInt8] = []
        result.reserveCapacity(bytes.count + insertions.count * 24)
        var copied = 0
        for insertion in insertions {
            result.append(contentsOf: bytes[copied..<insertion.offset])
            result.append(contentsOf: insertion.text.utf8)
            copied = insertion.offset
        }
        result.append(contentsOf: bytes[copied...])
        return String(bytes: result, encoding: .utf8) ?? html
    }

    private static func token(for quote: VisibilityPolicy.Quote, hidesAuthor: Bool) -> String? {
        switch quote {
        case .ofMe: "quote-me"
        case .allowlisted: "quote-allowed"
        case .blocked: hidesAuthor ? "quote-blocked quote-hide-author" : "quote-blocked"
        case .normal: nil
        }
    }

    /// Offset of the next `<table` start tag at or after `from`.
    private static func nextTable(in bytes: [UInt8], from: Int) -> Int? {
        let needle = Array("<table".utf8)
        var index = from
        while index + needle.count < bytes.count {
            if bytes[index] == needle[0], bytes[index..<(index + needle.count)].elementsEqual(needle) {
                let next = bytes[index + needle.count]
                if next == 0x20 || next == 0x3E || next == 0x0A || next == 0x09 || next == 0x2F { return index }
            }
            index += 1
        }
        return nil
    }

    /// Offset just after the `>` that closes the tag opened at `start`; quoted attribute values may hold a `>`.
    private static func endOfTag(in bytes: [UInt8], from start: Int) -> Int {
        var quote: UInt8?
        var index = start
        while index < bytes.count {
            let byte = bytes[index]
            if let open = quote {
                if byte == open { quote = nil }
            } else if byte == 0x22 || byte == 0x27 {
                quote = byte
            } else if byte == 0x3E {
                return index + 1
            }
            index += 1
        }
        return bytes.count
    }

    /// Range of the value of the `class` attribute of the tag, between its double quotes.
    private static func classValue(in bytes: [UInt8], tag: Range<Int>) -> Range<Int>? {
        let needle = Array(" class=\"".utf8)
        var index = tag.lowerBound
        var quote: UInt8?
        while index < tag.upperBound {
            let byte = bytes[index]
            if let open = quote {
                if byte == open { quote = nil }
            } else if byte == 0x22 || byte == 0x27 {
                quote = byte
            } else if byte == 0x20, index + needle.count <= tag.upperBound, bytes[index..<(index + needle.count)].elementsEqual(needle) {
                let valueStart = index + needle.count
                guard let close = bytes[valueStart..<tag.upperBound].firstIndex(of: 0x22) else { return nil }
                return valueStart..<close
            }
            index += 1
        }
        return nil
    }

    private static func isQuote(_ value: ArraySlice<UInt8>) -> Bool {
        (String(bytes: value, encoding: .utf8) ?? "").split(whereSeparator: \.isWhitespace).contains { quoteClasses.contains(String($0)) }
    }
}
