import Foundation
@testable import SwiftHFR
import Testing

/// Where a picked smiley lands (#910): over the range the editor had when the picker opened, between two spaces, the caret
/// right after it, in UTF-16 units; formatting tags still wrap a selection.
@MainActor
struct SmileyInsertionTests {
    private func make(_ text: String) async -> (ReplyComposerModel, ComposerFormattingModel) {
        let composer = ComposerFixture.model(poster: ScriptedPoster([]))
        await composer.start()
        composer.update(text: text)
        return (composer, ComposerFormattingModel(composer: composer, clipboard: EmptyClipboard()))
    }

    @Test func aCaretInTheMiddleInsertsThereNotAtTheEnd() async {
        let (composer, formatting) = await make("Salut toi")
        // The editor's live selection moved (focus lost) after this range was captured: the captured one decides.
        formatting.selectedRange = NSRange(location: 9, length: 0)
        let before = formatting.cursorRevision
        #expect(formatting.insert(smiley: ":)", at: NSRange(location: 5, length: 0)))
        #expect(composer.text == "Salut :)  toi")
        #expect(formatting.selectedRange == NSRange(location: 9, length: 0))
        #expect(formatting.cursorRevision == before + 1)
    }

    @Test func aSelectionIsReplaced() async {
        let (composer, formatting) = await make("un deux trois")
        #expect(formatting.insert(smiley: ":o", at: NSRange(location: 3, length: 4)))
        #expect(composer.text == "un  :o  trois")
        #expect(formatting.selectedRange == NSRange(location: 7, length: 0))
    }

    @Test func aCaretAtTheEndAppends() async {
        let (composer, formatting) = await make("ok")
        #expect(formatting.insert(smiley: ":love:", at: NSRange(location: 2, length: 0)))
        #expect(composer.text == "ok :love: ")
        #expect(formatting.selectedRange.location == 10)
    }

    @Test func theCaretCountsUTF16UnitsAfterAccentsAndEmoji() async {
        let text = "é😀 fin"
        let (composer, formatting) = await make(text)
        #expect(formatting.insert(smiley: ":)", at: NSRange(location: 3, length: 0)))
        #expect(composer.text == "é😀 :)  fin")
        #expect(formatting.selectedRange.location == 3 + " :) ".utf16.count)
    }

    @Test func aStaleRangeIsClampedInsteadOfTrapping() async {
        let (composer, formatting) = await make("ab")
        #expect(formatting.insert(smiley: ":)", at: NSRange(location: 40, length: 3)))
        #expect(composer.text == "ab :) ")
    }

    @Test func aCodeWithPunctuationIsInsertedVerbatim() async {
        let (composer, formatting) = await make("")
        #expect(formatting.insert(smiley: "[:exemple]", at: NSRange(location: 0, length: 0)))
        #expect(composer.text == " [:exemple] ")
    }

    @Test func aTagStillWrapsTheSelectionAfterASmiley() async {
        let (composer, formatting) = await make("un deux trois")
        #expect(formatting.insert(smiley: ":)", at: NSRange(location: 0, length: 0)))
        formatting.selectedRange = NSRange(location: 7, length: 4)
        formatting.tap(.bbCode(.bold))
        #expect(composer.text == " :) un [b]deux[/b] trois")
    }
}
