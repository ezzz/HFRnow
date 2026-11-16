import Foundation
import SwiftUI
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
        formatting.selectedRange = NSRange(location: 5, length: 0)
        formatting.beginPick()
        // The sheet took focus and the live caret moved: the range saved when it opened decides.
        formatting.selectedRange = NSRange(location: 9, length: 0)
        let before = formatting.cursorRevision
        #expect(formatting.insert(smiley: ":)"))
        #expect(composer.text == "Salut :)  toi")
        #expect(formatting.selectedRange == NSRange(location: 9, length: 0))
        #expect(formatting.cursorRevision == before + 1)
    }

    @Test func aSelectionIsReplaced() async {
        let (composer, formatting) = await make("un deux trois")
        formatting.selectedRange = NSRange(location: 3, length: 4)
        formatting.beginPick()
        #expect(formatting.insert(smiley: ":o"))
        #expect(composer.text == "un  :o  trois")
        #expect(formatting.selectedRange == NSRange(location: 7, length: 0))
    }

    @Test func aCaretAtTheEndAppends() async {
        let (composer, formatting) = await make("ok")
        formatting.selectedRange = NSRange(location: 2, length: 0)
        formatting.beginPick()
        #expect(formatting.insert(smiley: ":love:"))
        #expect(composer.text == "ok :love: ")
        #expect(formatting.selectedRange.location == 10)
    }

    @Test func theCaretCountsUTF16UnitsAfterAccentsAndEmoji() async {
        let text = "é😀 fin"
        let (composer, formatting) = await make(text)
        formatting.selectedRange = NSRange(location: 3, length: 0)
        formatting.beginPick()
        #expect(formatting.insert(smiley: ":)"))
        #expect(composer.text == "é😀 :)  fin")
        #expect(formatting.selectedRange.location == 3 + " :) ".utf16.count)
    }

    @Test func aStaleRangeIsClampedInsteadOfTrapping() async {
        let (composer, formatting) = await make("ab")
        formatting.selectedRange = NSRange(location: 40, length: 3)
        formatting.beginPick()
        #expect(formatting.insert(smiley: ":)"))
        #expect(composer.text == "ab :) ")
    }

    @Test func aCodeWithPunctuationIsInsertedVerbatim() async {
        let (composer, formatting) = await make("")
        formatting.selectedRange = NSRange(location: 0, length: 0)
        formatting.beginPick()
        #expect(formatting.insert(smiley: "[:exemple]"))
        #expect(composer.text == " [:exemple] ")
    }

    @Test func aTagStillWrapsTheSelectionAfterASmiley() async {
        let (composer, formatting) = await make("un deux trois")
        formatting.selectedRange = NSRange(location: 0, length: 0)
        formatting.beginPick()
        #expect(formatting.insert(smiley: ":)"))
        formatting.selectedRange = NSRange(location: 7, length: 4)
        formatting.tap(.bbCode(.bold))
        #expect(composer.text == " :) un [b]deux[/b] trois")
    }
}

/// What the image and GIF sheets insert at, and how the editor card keeps the range (#910).
@MainActor
struct PickedRangeTests {
    private func make(_ text: String) async -> (ReplyComposerModel, ComposerFormattingModel) {
        let composer = ComposerFixture.model(poster: ScriptedPoster([]))
        await composer.start()
        composer.update(text: text)
        return (composer, ComposerFormattingModel(composer: composer, clipboard: EmptyClipboard()))
    }

    @Test func anImageOrGifSnippetLandsWhereTheSheetOpened() async {
        let (composer, formatting) = await make("Salut toi")
        formatting.selectedRange = NSRange(location: 5, length: 0)
        formatting.beginPick()
        formatting.selectedRange = NSRange(location: 9, length: 0)
        formatting.insertPicked("[img]x[/img]")
        #expect(composer.text == "Salut[img]x[/img] toi")
    }

    @Test func aNilSelectionKeepsTheRangeTheModelHad() {
        let current = NSRange(location: 5, length: 2)
        #expect(ComposerEditorCard.syncedRange(nil, current: current, in: "Salut toi") == current)
    }

    @Test func aCaretSelectionGivesItsRange() {
        let text = "Salut toi"
        let caret = TextSelection(insertionPoint: text.index(text.startIndex, offsetBy: 5))
        #expect(ComposerEditorCard.syncedRange(caret, current: NSRange(location: 0, length: 0), in: text) == NSRange(location: 5, length: 0))
    }

    @Test func aMultiSelectionGivesItsFirstRange() {
        let text = "un deux trois"
        let first = text.index(text.startIndex, offsetBy: 3)..<text.index(text.startIndex, offsetBy: 7)
        let last = text.index(text.endIndex, offsetBy: -5)..<text.endIndex
        let selection = TextSelection(ranges: RangeSet([first, last]))
        #expect(ComposerEditorCard.syncedRange(selection, current: NSRange(location: 0, length: 0), in: text) == NSRange(location: 3, length: 4))
    }
}
