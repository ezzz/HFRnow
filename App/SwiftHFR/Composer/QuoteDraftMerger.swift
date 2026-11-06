import Foundation

// Port of HFRswift/Swift/MessagesView.swift (`ReplyQuoteDraftMerger`, :15-34) @ 21173e7 (`master`; the type is newer than
// 2440d79 and has no call site there: legacy's quote entries archived the draft and replaced it, `replaceComposerDraft`).
// Differences: the quote entries merge into the draft (docs/lots/LOT-086-quote-composer.md, difference 7); the "already in
// the draft" test is exact; legacy's `localizedStandardContains` also ignores case and diacritics, so a draft that merely
// spells the quote's words in another case would have dropped the quote.
/// Puts a quote into the text already written (LOT-086).
enum QuoteDraftMerger {
    /// `draft` with `quote` after it, a blank line between. An empty draft becomes the quote as served; a blank quote, or a
    /// quote the draft already holds whole, changes nothing.
    static func merge(_ quote: String, into draft: String) -> String {
        let trimmedQuote = quote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuote.isEmpty else { return draft }
        guard !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return quote }
        if draft.contains(trimmedQuote) { return draft }
        return draft + (draft.hasSuffix("\n") ? "\n" : "\n\n") + quote
    }
}

/// The order of the blocks of a multi-quote prefill (LOT-086, "quote order = topic order").
enum MultiQuoteOrder {
    /// `prefill` with its `[quotemsg=<numreponse>,…]…[/quotemsg]` blocks by ascending message number (a topic's order),
    /// whole and as served, ties kept in their order. A prefill that holds anything but quote blocks, or has fewer than two,
    /// is returned unchanged: the app never rewrites what HFR wrote (HFR-PROTOCOL §4). The captured composers (`R42`,
    /// `R47c`) list their blocks by ascending number already; what HFR does with another cookie order is pending capture.
    static func topicOrder(_ prefill: String) -> String {
        let blocks = prefill.matches(of: /\[quotemsg=([0-9]+),[0-9]+,[0-9]+\][\s\S]*?\[\/quotemsg\][ \t\r\n]*/.ignoresCase())
        guard blocks.count > 1 else { return prefill }
        let texts = blocks.map { String($0.output.0) }
        guard texts.joined() == String(prefill.drop(while: \.isWhitespace)) else { return prefill }
        let numbers = blocks.map { Int($0.output.1) ?? Int.max }
        let sorted = texts.indices.sorted { numbers[$0] != numbers[$1] ? numbers[$0] < numbers[$1] : $0 < $1 }
        return sorted.map { texts[$0] }.joined()
    }
}
