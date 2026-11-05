import Foundation

// Port of HFRswift/Swift/ReplyComposer.swift (ReplyTextInsertionEngine.insert) @ 2440d79. Differences: UTF-16 caret offset
// for SwiftUI TextSelection, snippet fixed to the smiley one (GAP-087).
/// Where a smiley code lands in the reply text (LOT-104).
///
/// Port of `ReplyTextInsertionEngine.insert` (`HFRswift/Swift/ReplyComposer.swift:176-196` @ 2440d79) with the snippet
/// legacy built for a smiley (`insertSmileyCode`, `AnswerView.swift:~517`: the code between two spaces). Pure: the view
/// reads the selection, this decides the text and the caret.
enum SmileyInsertion {
    /// The text after the insertion and where the caret goes, as a UTF-16 offset into `text`.
    struct Result: Equatable {
        let text: String
        let caretUTF16Offset: Int
    }

    /// What is written for `code`: the code between two spaces, as legacy did.
    static func snippet(for code: String) -> String {
        " \(code) "
    }

    /// Inserts `code` over `selection` (a caret is an empty range), or at the end when there is no selection.
    static func insert(_ code: String, into text: String, replacing selection: Range<String.Index>?) -> Result {
        let snippet = snippet(for: code)
        guard let selection else {
            let newText = text + snippet
            return Result(text: newText, caretUTF16Offset: newText.utf16.count)
        }
        let start = text.utf16.distance(from: text.utf16.startIndex, to: selection.lowerBound)
        var newText = text
        newText.replaceSubrange(selection, with: snippet)
        return Result(text: newText, caretUTF16Offset: start + snippet.utf16.count)
    }
}
