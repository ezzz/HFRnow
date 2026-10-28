import Foundation
import HFRModels
import SwiftSoup

/// Reads the quote blocks of a message: author, nesting depth and the cited message number.
///
/// Port of the quote classification of `ParseMessagesOperation.parseData:` (`ParseMessagesOperation.m:191-226`: `oldcitation`
/// counted as `citation`, author = text of the header `Topic` element minus its last 10 characters), extended with the facts
/// legacy never computed (cited number, depth, anonymous quotes). Policy (own pseudo, blacklist, whitelist) stays app-side.
/// Works on the raw content of LOT-030 and on the sanitized HTML of LOT-034: both keep `table.citation|oldcitation|quote`,
/// `a.Topic` and its `#t<n>` link.
public enum MessageQuoteAnalyzer {
    /// Quotes of a content fragment in document order, an outer quote before the quotes it contains.
    /// - Throws: `malformedDocument` when the HTML backend cannot read the fragment.
    public static func quotes(inContentHTML html: String) throws(ParsingError) -> [MessageQuote] {
        guard let body = (try? SwiftSoup.parseBodyFragment(html))?.body() else { throw .malformedDocument }
        return quotes(in: body)
    }

    /// Same from the content element of an `ExtractedMessageBlock`; the tree is read, never mutated.
    static func quotes(in content: Element) -> [MessageQuote] {
        var found: [Found] = []
        // Iterative walk: SwiftSoup's own recursive helpers (`select`, `parents`) overflow the stack on deeply nested markup.
        var open: [Int] = []
        var pending: [Step] = content.children().array().reversed().map { .enter($0) }
        while let step = pending.popLast() {
            switch step {
            case .leave:
                open.removeLast()
            case .enter(let element):
                if isQuote(element) {
                    found.append(Found(depth: open.count + 1, authored: isAuthored(element)))
                    open.append(found.count - 1)
                    pending.append(.leave)
                } else if let owner = open.last, found[owner].authored, found[owner].header == nil, isHeader(element) {
                    found[owner].header = element
                }
                pending.append(contentsOf: element.children().array().reversed().map { .enter($0) })
            }
        }
        return found.map { quote in
            guard let header = quote.header else { return MessageQuote(depth: quote.depth) }
            return MessageQuote(author: author(in: header), depth: quote.depth, citedNumreponse: citedNumreponse(in: header))
        }
    }

    // MARK: - Internals

    private enum Step {
        case enter(Element)
        case leave
    }

    private struct Found {
        var depth: Int
        var authored: Bool
        var header: Element?
    }

    /// Whole class tokens HFR gives a quote table: author quotes (current and old markup) and anonymous ones.
    private static let authoredClasses: Set<String> = ["citation", "oldcitation"]
    private static let anonymousClass = "quote"
    /// Suffix of the header text, after the author (legacy cut the last 10 characters blindly).
    // `Regex` is not `Sendable` (its output type could hold non-Sendable captures). This literal has no captures
    // and the compiled program is initialised atomically by the runtime, so sharing is safe (as in `HFRText`).
    nonisolated(unsafe) private static let headerSuffix = /\s*a\s+écrit\s*:\s*$/

    private static func classTokens(of element: Element) -> [Substring] {
        ((try? element.attr("class")) ?? "").htmlClassTokens
    }

    private static func isAuthored(_ table: Element) -> Bool {
        classTokens(of: table).contains { authoredClasses.contains(String($0)) }
    }

    private static func isQuote(_ element: Element) -> Bool {
        element.tagName() == "table" && classTokens(of: element).contains { authoredClasses.contains(String($0)) || $0 == anonymousClass }
    }

    /// The legacy header lookup: the whole class attribute is `Topic` (a spoiler's `div.Topic.masque` is not one).
    private static func isHeader(_ element: Element) -> Bool {
        element.tagName() == "a" && element.hasAttr("class") && (try? element.attr("class")) == "Topic"
    }

    private static func author(in header: Element) -> String? {
        let text = ((try? header.text()) ?? "").replacing("\u{00A0}", with: " ")
        let name = HFRText.normalizedPseudo(text.replacing(headerSuffix, with: ""))
        // Without the suffix the header is not "<author> a écrit :": no author rather than a guess.
        guard text.contains(headerSuffix), !name.isEmpty else { return nil }
        return name
    }

    /// Number of the cited message: the whole fragment of the header link must be `t<digits>`.
    private static func citedNumreponse(in header: Element) -> Int? {
        guard let href = try? header.attr("href"), let hash = href.lastIndex(of: "#") else { return nil }
        guard let match = href[href.index(after: hash)...].wholeMatch(of: /t([0-9]+)/) else { return nil }
        return Int(match.1)
    }
}
