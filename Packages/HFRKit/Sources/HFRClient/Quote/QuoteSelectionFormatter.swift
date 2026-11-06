import Foundation

/// Narrows HFR's quote prefill to the text the user selected in the message, or bolds that text in it: a port of
/// `ReplyQuoteSelectionFormatter` (`MessagesView.swift:36-109`; ObjC `QuoteMessageViewController.m:459-525`).
///
/// The `[quotemsg=…]` tags stay HFR's, as served: legacy Swift rebuilt the opening tag from its three numbers, and legacy
/// ObjC through `int`, which wraps on large message numbers. The selection is looked for in the text of the blocks
/// only, outside every BBCode tag: legacy also searched the tags, so selecting "2" could bold a digit inside
/// `[quotemsg=…]`, and a link's label could be bolded inside its `[url=…]` attribute.
public enum QuoteSelectionFormatter {
    /// The prefill for `selection`; `bold` keeps the whole quote with the selection in `[b]…[/b]`.
    ///
    /// - One block: without `bold`, its text becomes the selection, which is not looked for (it is read on the rendered
    ///   message, whose text is not the BBCode: smileys, links); with `bold`, the first occurrence of the selection,
    ///   case-insensitive, is wrapped, and the prefill is returned unchanged when there is none.
    /// - Several blocks (multi-quote): the first block whose text holds the selection, case-insensitive, is returned
    ///   alone, narrowed or bolded; when none holds it (a selection over two messages), the prefill is unchanged.
    /// - An empty selection (once whitespace and newlines are trimmed), or a prefill without block, changes nothing.
    public static func format(_ prefill: String, selection: String, bold: Bool) -> String {
        let selected = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !selected.isEmpty else { return prefill }
        let pattern = /(\[quotemsg=[0-9]+,[0-9]+,[0-9]+\])(.*?)(\[\/quotemsg\])/.ignoresCase().dotMatchesNewlines()
        let blocks = prefill.matches(of: pattern)
        if blocks.count > 1 {
            guard let block = blocks.first(where: { visibleRange(of: selected, in: String($0.output.2)) != nil }) else {
                return prefill
            }
            let (_, opening, text, closing) = block.output
            let formatted = bold ? bolded(String(text), selection: selected) ?? String(text) : selected
            return String(opening) + formatted + String(closing) + "\n"
        }
        guard let block = blocks.first else { return prefill }
        let (_, opening, text, closing) = block.output
        guard bold else { return String(opening) + selected + String(closing) + "\n" }
        guard let formatted = bolded(String(text), selection: selected) else { return prefill }
        var result = prefill
        result.replaceSubrange(text.startIndex..<text.endIndex, with: formatted)
        return result.hasSuffix("\n") ? result : result + "\n"
    }

    /// `text` with the first visible case-insensitive occurrence of `selection` wrapped in `[b]…[/b]`, as typed in the message.
    private static func bolded(_ text: String, selection: String) -> String? {
        guard let range = visibleRange(of: selection, in: text) else { return nil }
        return text.replacingCharacters(in: range, with: "[b]" + text[range] + "[/b]")
    }

    /// The first case-insensitive occurrence of `selection` in `text` that overlaps no BBCode tag. The selection is read on
    /// the rendered message, so it is never a tag's text: in `[url=https://example.org]example.org[/url]` the label is
    /// meant, not the attribute.
    private static func visibleRange(of selection: String, in text: String) -> Range<String.Index>? {
        let tags = text.matches(of: /\[[^\[\]]*\]/).map(\.range)
        var start = text.startIndex
        while let range = text.range(of: selection, options: .caseInsensitive, range: start..<text.endIndex) {
            if !tags.contains(where: { $0.overlaps(range) }) { return range }
            start = text.index(after: range.lowerBound)
        }
        return nil
    }
}
