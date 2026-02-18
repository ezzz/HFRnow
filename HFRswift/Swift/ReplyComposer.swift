import Foundation

enum ReplyComposerPanel: Equatable {
    case none
    case defaultSmileys
    case favoriteSmileys
    case imageInsertion
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

enum ReplyTextInsertionEngine {
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
