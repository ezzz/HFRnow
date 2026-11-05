import Foundation

/// New text and where the caret goes (UTF-16 offset, as `NSRange` and `UITextView` count).
struct ReplyTextInsertionResult: Equatable {
    let text: String
    let cursorLocationUTF16: Int
}

// Port of HFRswift/Swift/ReplyComposer.swift (BBCodeTag) @ origin/master 21173e7. Differences: none.
/// The BBCode tags of the toolbar, in legacy order.
enum BBCodeTag: String, CaseIterable, Sendable {
    case bold = "b"
    case italic = "i"
    case underline = "u"
    case strike
    case spoiler
    case quote
    case url
    case img
    case fixed

    /// The French label (accessibility and menus).
    var label: String {
        switch self {
        case .bold: "Gras"
        case .italic: "Italique"
        case .underline: "Souligné"
        case .strike: "Barré"
        case .spoiler: "Spoiler"
        case .quote: "Citation"
        case .url: "Lien"
        case .img: "Image"
        case .fixed: "Code"
        }
    }

    /// The SF Symbol of the button.
    var systemImage: String {
        switch self {
        case .bold: "bold"
        case .italic: "italic"
        case .underline: "underline"
        case .strike: "strikethrough"
        case .spoiler: "eye.slash"
        case .quote: "quote.opening"
        case .url: "link"
        case .img: "photo"
        case .fixed: "chevron.left.forwardslash.chevron.right"
        }
    }
}

// Port of HFRswift/Swift/AnswerView.swift (ReplyTextColor) @ origin/master 21173e7. Differences: none.
/// One colour of the palette; `[<hex>]…[/<hex>]` is HFR's colour tag as the legacy composer writes it.
struct ReplyTextColor: Identifiable, Hashable, Sendable {
    let name: String
    let hex: String

    var id: String { hex }

    /// The 16 colours of the legacy palette, in legacy order.
    static let palette: [ReplyTextColor] = [
        ReplyTextColor(name: "Noir", hex: "000000"),
        ReplyTextColor(name: "Gris", hex: "808080"),
        ReplyTextColor(name: "Argent", hex: "c0c0c0"),
        ReplyTextColor(name: "Blanc", hex: "ffffff"),
        ReplyTextColor(name: "Rouge", hex: "ff0000"),
        ReplyTextColor(name: "Bordeaux", hex: "800000"),
        ReplyTextColor(name: "Orange", hex: "ff8000"),
        ReplyTextColor(name: "Jaune", hex: "ffff00"),
        ReplyTextColor(name: "Vert", hex: "00ff00"),
        ReplyTextColor(name: "Vert foncé", hex: "008000"),
        ReplyTextColor(name: "Cyan", hex: "00ffff"),
        ReplyTextColor(name: "Turquoise", hex: "008080"),
        ReplyTextColor(name: "Bleu", hex: "0000ff"),
        ReplyTextColor(name: "Bleu marine", hex: "000080"),
        ReplyTextColor(name: "Magenta", hex: "ff00ff"),
        ReplyTextColor(name: "Violet", hex: "800080")
    ]
}

/// What a toolbar button wraps the selection with.
enum ReplyFormattingTarget: Equatable, Sendable {
    case bbCode(BBCodeTag)
    case color(ReplyTextColor)

    /// The name inside the brackets.
    var rawTag: String {
        switch self {
        case .bbCode(let tag): tag.rawValue
        case .color(let color): color.hex
        }
    }

    /// The French label, as the clipboard confirmation names it.
    var label: String {
        switch self {
        case .bbCode(let tag): tag.label
        case .color(let color): "Couleur \(color.name)"
        }
    }
}

// Port of HFRswift/Swift/ReplyComposer.swift (ReplyTextInsertionEngine) @ origin/master 21173e7. Differences: the
// legacy `wrapWithBBCode(_ tag:)` overload is folded into `wrapWithBBCode(rawTag:)`; ranges are clamped here (legacy
// clamped in the view).
/// Pure text edits of the composer: wrap, insert, split a quote. UTF-16 ranges in and out; the caret is always returned
/// explicitly so the view never leaves it to jump to the end (feedback p. 506).
enum ReplyTextInsertionEngine {
    /// Clamps `range` into `text` and onto character boundaries, so a stale selection never splits a surrogate pair.
    static func clamped(_ range: NSRange, in text: String) -> NSRange {
        let count = text.utf16.count
        let location = max(0, min(range.location == NSNotFound ? count : range.location, count))
        let length = max(0, min(range.length, count - location))
        guard let swiftRange = Range(NSRange(location: location, length: length), in: text) else {
            return NSRange(location: count, length: 0)
        }
        return NSRange(swiftRange, in: text)
    }

    /// Wraps the selection in `[tag]…[/tag]`. Selection: the caret goes after the closing tag. No selection: the tags
    /// are inserted with the caret between them, or around `textForEmptySelection` (the clipboard text) with the caret
    /// after.
    static func wrapWithBBCode(
        rawTag: String,
        in text: String,
        selectedUTF16Range: NSRange,
        textForEmptySelection: String? = nil
    ) -> ReplyTextInsertionResult {
        let openTag = "[\(rawTag)]"
        let closeTag = "[/\(rawTag)]"
        let selection = clamped(selectedUTF16Range, in: text)
        guard let range = Range(selection, in: text) else {
            return ReplyTextInsertionResult(text: text, cursorLocationUTF16: text.utf16.count)
        }
        let hasSelection = selection.length > 0
        let inner = hasSelection ? String(text[range]) : (textForEmptySelection ?? "")
        let wrapped = openTag + inner + closeTag
        let cursor = selection.location
            + (hasSelection || textForEmptySelection != nil ? wrapped.utf16.count : openTag.utf16.count)
        return ReplyTextInsertionResult(text: text.replacingCharacters(in: range, with: wrapped), cursorLocationUTF16: cursor)
    }

    /// Wraps the selection in `[url=<url>]…[/url]`; without a selection it falls back to an empty `[url][/url]`.
    static func wrapSelectionWithURL(
        _ urlString: String,
        in text: String,
        selectedUTF16Range: NSRange
    ) -> ReplyTextInsertionResult {
        let selection = clamped(selectedUTF16Range, in: text)
        guard selection.length > 0, let range = Range(selection, in: text) else {
            return wrapWithBBCode(rawTag: BBCodeTag.url.rawValue, in: text, selectedUTF16Range: selection)
        }
        let wrapped = "[url=\(urlString)]\(text[range])[/url]"
        return ReplyTextInsertionResult(
            text: text.replacingCharacters(in: range, with: wrapped),
            cursorLocationUTF16: selection.location + wrapped.utf16.count
        )
    }

    /// Splits a `[quotemsg=…]…[/quotemsg]` block at the caret into two quotes with a blank line between, so the reply
    /// can be written in the middle. nil when the caret is not strictly inside a quote's content.
    static func splitQuote(in text: String, atUTF16Offset cursor: Int) -> ReplyTextInsertionResult? {
        guard let regex = try? NSRegularExpression(
            pattern: #"\[quotemsg=([^\]]+)\](.*?)\[/quotemsg\]"#,
            options: .dotMatchesLineSeparators
        ) else { return nil }
        let nsText = text as NSString
        for match in regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)) where match.numberOfRanges == 3 {
            let content = match.range(at: 2)
            guard cursor > content.location, cursor < NSMaxRange(content) else { continue }
            let params = nsText.substring(with: match.range(at: 1))
            let local = cursor - content.location
            let body = nsText.substring(with: content) as NSString
            let first = body.substring(to: local)
            let second = body.substring(from: local)
            let replacement = "[quotemsg=\(params)]\(first)[/quotemsg]\n\n\n[quotemsg=\(params)]\(second)[/quotemsg]"
            return ReplyTextInsertionResult(
                text: nsText.replacingCharacters(in: match.range, with: replacement),
                cursorLocationUTF16: cursor + ("[/quotemsg]" as NSString).length + 1
            )
        }
        return nil
    }

    /// Replaces the selection with `snippet` (a smiley code, a pasted link), the caret after it.
    static func insert(_ snippet: String, into text: String, selectedUTF16Range: NSRange) -> ReplyTextInsertionResult {
        let selection = clamped(selectedUTF16Range, in: text)
        guard !snippet.isEmpty, let range = Range(selection, in: text) else {
            return ReplyTextInsertionResult(text: text, cursorLocationUTF16: selection.location)
        }
        return ReplyTextInsertionResult(
            text: text.replacingCharacters(in: range, with: snippet),
            cursorLocationUTF16: selection.location + snippet.utf16.count
        )
    }
}
