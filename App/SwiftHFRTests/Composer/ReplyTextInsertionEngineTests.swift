import Foundation
@testable import SwiftHFR
import Testing

/// The pure edits, ported from the legacy engine (`ReplyComposer.swift` @ origin/master 21173e7).
struct ReplyTextInsertionEngineTests {
    private func wrap(_ tag: String, _ text: String, _ location: Int, _ length: Int = 0, clip: String? = nil) -> ReplyTextInsertionResult {
        ReplyTextInsertionEngine.wrapWithBBCode(
            rawTag: tag, in: text, selectedUTF16Range: NSRange(location: location, length: length), textForEmptySelection: clip
        )
    }

    @Test func wrapsASelectionAndPlacesTheCaretAfterTheClosingTag() {
        let result = wrap("b", "un deux trois", 3, 4)
        #expect(result.text == "un [b]deux[/b] trois")
        #expect(result.cursorLocationUTF16 == 3 + "[b]deux[/b]".utf16.count)
    }

    @Test func withoutSelectionTheCaretGoesBetweenTheTags() {
        let result = wrap("i", "abc", 1)
        #expect(result.text == "a[i][/i]bc")
        #expect(result.cursorLocationUTF16 == 4)
    }

    @Test func theCaretIsNeverLeftAtTheEnd() {
        // Regression of feedback p. 506: an insertion in the middle keeps the caret in the middle.
        let result = wrap("u", "début fin", 5)
        #expect(result.cursorLocationUTF16 == 8)
        #expect(result.cursorLocationUTF16 < result.text.utf16.count)
    }

    @Test func clipboardTextIsWrappedAndTheCaretGoesAfter() {
        let result = wrap("fixed", "x", 1, clip: "code")
        #expect(result.text == "x[fixed]code[/fixed]")
        #expect(result.cursorLocationUTF16 == result.text.utf16.count)
    }

    @Test func utf16OffsetsHoldWithEmojiAndAccents() {
        let result = wrap("b", "é😀 ok", 4, 2)
        #expect(result.text == "é😀 [b]ok[/b]")
        #expect(result.cursorLocationUTF16 == 4 + "[b]ok[/b]".utf16.count)
    }

    @Test func aStaleRangeIsClampedNotCrashing() {
        let result = wrap("b", "abc", 99, 5)
        #expect(result.text == "abc[b][/b]")
        #expect(result.cursorLocationUTF16 == 6)
    }

    @Test func colourTagsUseTheHex() {
        #expect(wrap("ff0000", "a", 0, 1).text == "[ff0000]a[/ff0000]")
        #expect(ReplyTextColor.palette.count == 16)
        #expect(Set(ReplyTextColor.palette.map(\.hex)).count == 16)
    }

    @Test func urlWrapsTheSelectionWithTheAddress() {
        let result = ReplyTextInsertionEngine.wrapSelectionWithURL(
            "https://example.org/", in: "voir ici", selectedUTF16Range: NSRange(location: 5, length: 3)
        )
        #expect(result.text == "voir [url=https://example.org/]ici[/url]")
        #expect(result.cursorLocationUTF16 == result.text.utf16.count)
    }

    @Test func urlWithoutSelectionFallsBackToEmptyTags() {
        let result = ReplyTextInsertionEngine.wrapSelectionWithURL("https://e.org", in: "a", selectedUTF16Range: NSRange(location: 1, length: 0))
        #expect(result.text == "a[url][/url]")
        #expect(result.cursorLocationUTF16 == 6)
    }

    @Test func insertReplacesTheSelection() {
        let result = ReplyTextInsertionEngine.insert(" :o ", into: "abcd", selectedUTF16Range: NSRange(location: 1, length: 2))
        #expect(result.text == "a :o d")
        #expect(result.cursorLocationUTF16 == 5)
    }

    @Test func splitQuoteCutsInsideTheContent() throws {
        let text = "[quotemsg=1,2,3]abcdef[/quotemsg]"
        let offset = "[quotemsg=1,2,3]abc".utf16.count
        let result = try #require(ReplyTextInsertionEngine.splitQuote(in: text, atUTF16Offset: offset))
        #expect(result.text == "[quotemsg=1,2,3]abc[/quotemsg]\n\n\n[quotemsg=1,2,3]def[/quotemsg]")
        #expect(result.cursorLocationUTF16 == offset + "[/quotemsg]".utf16.count + 1)
    }

    @Test func splitQuoteRefusesOutsideAndAtTheEdges() {
        let text = "x[quotemsg=1]abc[/quotemsg]"
        #expect(ReplyTextInsertionEngine.splitQuote(in: text, atUTF16Offset: 0) == nil)
        #expect(ReplyTextInsertionEngine.splitQuote(in: text, atUTF16Offset: "x[quotemsg=1]".utf16.count) == nil)
        #expect(ReplyTextInsertionEngine.splitQuote(in: text, atUTF16Offset: text.utf16.count) == nil)
    }

    @Test func tagsAndLabelsFollowTheLegacyOrder() {
        #expect(BBCodeTag.allCases.map(\.rawValue) == ["b", "i", "u", "strike", "spoiler", "quote", "url", "img", "fixed"])
        #expect(BBCodeTag.allCases.map(\.label).first == "Gras")
    }
}
