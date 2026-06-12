import XCTest
@testable import HFRswift

@MainActor
final class ReplyComposerStateTests: XCTestCase {
    func testComposerStateCanSendDependsOnPostingAndTrimmedMessage() {
        var state = ReplyComposerState(initialMessage: "   ")
        XCTAssertFalse(state.canSend)

        state.message = "hello"
        XCTAssertTrue(state.canSend)

        state.isPosting = true
        XCTAssertFalse(state.canSend)
    }

    func testComposerStateBeginAndEndPosting() {
        var state = ReplyComposerState(initialMessage: "ok")
        XCTAssertTrue(state.beginPosting())
        XCTAssertFalse(state.beginPosting())
        state.endPosting()
        XCTAssertFalse(state.isPosting)
    }

    func testComposerStateResetAfterSuccessfulPost() {
        var state = ReplyComposerState(
            initialMessage: "draft",
            isPosting: true,
            activePanel: .favoriteSmileys
        )

        state.resetAfterSuccessfulPost()

        XCTAssertEqual(state.message, "")
        XCTAssertFalse(state.isPosting)
        XCTAssertEqual(state.activePanel, .none)
    }

    func testTextInsertionAppendsWhenNoSelectionProvided() {
        let result = ReplyTextInsertionEngine.insert(":)", into: "Salut")
        XCTAssertEqual(result.text, "Salut:)")
        XCTAssertEqual(result.cursorLocationUTF16, "Salut:)".utf16.count)
    }

    func testTextInsertionReplacesSelectedRange() {
        let text = "bonjour monde"
        let selection = NSRange(location: 8, length: 5) // "monde"

        let result = ReplyTextInsertionEngine.insert("[b]toi[/b]", into: text, selectedUTF16Range: selection)

        XCTAssertEqual(result.text, "bonjour [b]toi[/b]")
        XCTAssertEqual(result.cursorLocationUTF16, "bonjour [b]toi[/b]".utf16.count)
    }

    func testTextInsertionFallsBackToAppendWhenSelectionIsInvalid() {
        let result = ReplyTextInsertionEngine.insert("[img]u[/img]", into: "abc", selectedUTF16Range: NSRange(location: 99, length: 1))
        XCTAssertEqual(result.text, "abc[img]u[/img]")
        XCTAssertEqual(result.cursorLocationUTF16, "abc[img]u[/img]".utf16.count)
    }

    func testURLInsertionUsesClipboardURLAsOpeningTagAttribute() {
        let text = "voir ce lien"
        let selection = NSRange(location: 5, length: 7) // "ce lien"

        let result = ReplyTextInsertionEngine.wrapSelectionWithURL(
            "https://example.com/topic#post",
            in: text,
            selectedUTF16Range: selection
        )

        XCTAssertEqual(result.text, "voir [url=https://example.com/topic#post]ce lien[/url]")
        XCTAssertEqual(result.cursorLocationUTF16, "voir [url=https://example.com/topic#post]ce lien[/url]".utf16.count)
    }
}
