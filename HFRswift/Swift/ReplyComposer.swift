import Foundation

enum ReplyComposerPanel: String, Equatable, Identifiable {
    case none
    case defaultSmileys
    case favoriteSmileys
    case imageInsertion

    var id: String { rawValue }
}

struct ReplyComposerState: Equatable {
    var message: String
    var isPosting: Bool
    var activePanel: ReplyComposerPanel

    init(
        initialMessage: String = "",
        isPosting: Bool = false,
        activePanel: ReplyComposerPanel = .none
    ) {
        self.message = initialMessage
        self.isPosting = isPosting
        self.activePanel = activePanel
    }

    var trimmedMessage: String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canSend: Bool {
        !isPosting && !trimmedMessage.isEmpty
    }

    mutating func beginPosting() -> Bool {
        guard !isPosting else { return false }
        isPosting = true
        return true
    }

    mutating func endPosting() {
        isPosting = false
    }

    mutating func resetAfterSuccessfulPost() {
        message = ""
        activePanel = .none
        isPosting = false
    }
}

struct ReplyTextInsertionResult: Equatable {
    let text: String
    let cursorLocationUTF16: Int
}

// MARK: - BBCode

enum BBCodeTag: String, CaseIterable {
    case bold = "b"
    case italic = "i"
    case underline = "u"
    case strike = "strike"
    case spoiler = "spoiler"
    case quote = "quote"
    case url = "url"
    case img = "img"
    case fixed = "fixed"

    var label: String {
        switch self {
        case .bold: return "Gras"
        case .italic: return "Italique"
        case .underline: return "Souligné"
        case .strike: return "Barré"
        case .spoiler: return "Spoiler"
        case .quote: return "Citation"
        case .url: return "Lien"
        case .img: return "Image"
        case .fixed: return "Code"
        }
    }

    var systemImage: String? {
        switch self {
        case .bold: return "bold"
        case .italic: return "italic"
        case .underline: return "underline"
        case .strike: return "strikethrough"
        case .spoiler: return "eye.slash"
        case .quote: return "quote.opening"
        case .url: return "link"
        case .img: return "photo"
        case .fixed: return "chevron.left.forwardslash.chevron.right"
        }
    }
}

enum ReplyTextInsertionEngine {

    // MARK: BBCode wrapping

    static func wrapWithBBCode(
        _ tag: BBCodeTag,
        in text: String,
        selectedUTF16Range: NSRange
    ) -> ReplyTextInsertionResult {
        let openTag = "[\(tag.rawValue)]"
        let closeTag = "[/\(tag.rawValue)]"
        let hasSelection = selectedUTF16Range.length > 0

        guard let range = Range(selectedUTF16Range, in: text) else {
            // Fallback: append at end with cursor between tags
            let newText = text + openTag + closeTag
            return ReplyTextInsertionResult(
                text: newText,
                cursorLocationUTF16: text.utf16.count + openTag.utf16.count
            )
        }

        let selectedText = String(text[range])
        let wrapped = openTag + selectedText + closeTag
        let newText = text.replacingCharacters(in: range, with: wrapped)
        let prefixUTF16Count = text[..<range.lowerBound].utf16.count

        let cursorLocation: Int
        if hasSelection {
            // Cursor after closing tag
            cursorLocation = prefixUTF16Count + wrapped.utf16.count
        } else {
            // Cursor between opening and closing tag
            cursorLocation = prefixUTF16Count + openTag.utf16.count
        }
        return ReplyTextInsertionResult(text: newText, cursorLocationUTF16: cursorLocation)
    }

    // MARK: Split quote

    /// Splits a [quotemsg=...]...[/quotemsg] block at the given cursor offset.
    /// Returns nil if the cursor is not inside a quotemsg block.
    static func splitQuote(in text: String, atUTF16Offset cursorUTF16: Int) -> ReplyTextInsertionResult? {
        guard let regex = try? NSRegularExpression(
            pattern: #"\[quotemsg=([^\]]+)\](.*?)\[/quotemsg\]"#,
            options: .dotMatchesLineSeparators
        ) else { return nil }

        let nsText = text as NSString
        let fullLength = nsText.length
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: fullLength))

        for match in matches {
            guard match.numberOfRanges == 3 else { continue }
            let fullRange = match.range(at: 0)
            let paramsRange = match.range(at: 1)
            let contentRange = match.range(at: 2)

            guard cursorUTF16 > contentRange.location,
                  cursorUTF16 < NSMaxRange(contentRange) else { continue }

            let params = nsText.substring(with: paramsRange)
            let content = nsText.substring(with: contentRange)
            let localIndex = cursorUTF16 - contentRange.location
            let firstPart = (content as NSString).substring(to: localIndex)
            let secondPart = (content as NSString).substring(from: localIndex)

            let newQuote = "[quotemsg=\(params)]\(firstPart)[/quotemsg]\n\n\n[quotemsg=\(params)]\(secondPart)[/quotemsg]"
            let newText = nsText.replacingCharacters(in: fullRange, with: newQuote)
            let newCursorLocation = cursorUTF16 + ("[/quotemsg]" as NSString).length + 1 // +1 for newline
            return ReplyTextInsertionResult(text: newText, cursorLocationUTF16: newCursorLocation)
        }
        return nil
    }

    // MARK: Plain insertion

    static func insert(
        _ snippet: String,
        into text: String,
        selectedUTF16Range: NSRange? = nil
    ) -> ReplyTextInsertionResult {
        guard !snippet.isEmpty else {
            let location = normalizedSelectionStart(in: text, selectedUTF16Range: selectedUTF16Range)
            return ReplyTextInsertionResult(text: text, cursorLocationUTF16: location)
        }

        guard let selectedRange = selectedUTF16Range,
              let range = Range(selectedRange, in: text) else {
            let newText = text + snippet
            return ReplyTextInsertionResult(text: newText, cursorLocationUTF16: newText.utf16.count)
        }

        let prefixUTF16Count = text[..<range.lowerBound].utf16.count
        let newText = text.replacingCharacters(in: range, with: snippet)
        let cursorLocation = prefixUTF16Count + snippet.utf16.count
        return ReplyTextInsertionResult(text: newText, cursorLocationUTF16: cursorLocation)
    }

    private static func normalizedSelectionStart(in text: String, selectedUTF16Range: NSRange?) -> Int {
        guard let selectedUTF16Range,
              let range = Range(selectedUTF16Range, in: text) else {
            return text.utf16.count
        }
        return text[..<range.lowerBound].utf16.count
    }
}
