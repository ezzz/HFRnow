import Foundation
@testable import SwiftHFR
import Testing

/// Where a smiley code lands: over the selection with a space on each side, at the end without one (legacy
/// `ReplyTextInsertionEngine.insert`), the caret right after it, in UTF-16 units.
struct SmileyInsertionTests {
    @Test func aCaretInsertsTheCodeBetweenTwoSpaces() {
        let text = "Salut toi"
        let caret = text.index(text.startIndex, offsetBy: 5)
        let result = SmileyInsertion.insert(":)", into: text, replacing: caret..<caret)
        #expect(result == SmileyInsertion.Result(text: "Salut  :) toi", caretUTF16Offset: 9))
    }

    @Test func aSelectionIsReplaced() throws {
        let text = "un deux trois"
        let range = try #require(text.range(of: "deux"))
        let result = SmileyInsertion.insert(":o", into: text, replacing: range)
        #expect(result.text == "un  :o  trois")
        #expect(result.caretUTF16Offset == 7)
    }

    @Test func noSelectionAppendsAtTheEnd() {
        let result = SmileyInsertion.insert(":love:", into: "ok", replacing: nil)
        #expect(result == SmileyInsertion.Result(text: "ok :love: ", caretUTF16Offset: 10))
    }

    @Test func theCaretCountsUTF16UnitsAfterAccentsAndEmoji() {
        let text = "é😀"
        let end = text.endIndex
        let result = SmileyInsertion.insert(":)", into: text, replacing: end..<end)
        #expect(result.caretUTF16Offset == (text + " :) ").utf16.count)
        let reopened = String.Index(utf16Offset: result.caretUTF16Offset, in: result.text)
        #expect(reopened == result.text.endIndex)
    }

    @Test func aCodeWithPunctuationIsInsertedVerbatim() {
        let result = SmileyInsertion.insert("[:exemple]", into: "", replacing: nil)
        #expect(result.text == " [:exemple] ")
    }
}
