import Foundation
import HFRStorage
@testable import SwiftHFR
import Testing

/// Clear, undo and redo of the control row (#653, legacy `AnswerView.swift:624-635`, `:1345-1374` @ 87fe0d1c): every change of the
/// text is one step, insertions included, at most 200 kept; disabled with nothing to undo or redo and while the editor is locked.
@MainActor
struct ComposerHistoryTests {
    private func started(_ text: String = "") async -> ReplyComposerModel {
        let composer = ComposerFixture.model(poster: ScriptedPoster([]))
        await composer.start()
        if !text.isEmpty { composer.update(text: text) }
        return composer
    }

    @Test func theHistoryKeepsTheLast200TextsAndForgetsRedoOnANewChange() {
        var history = ComposerHistory()
        for index in 0..<205 { history.record("t\(index)") }
        #expect(history.undoCount == 200)
        #expect(history.undo(from: "now") == "t204")
        #expect(history.canRedo)
        history.record("typed")
        #expect(!history.canRedo)
    }

    @Test func undoAndRedoWalkTheHistoryBothWays() {
        var history = ComposerHistory()
        history.record("a")
        history.record("ab")
        #expect(history.undo(from: "abc") == "ab")
        #expect(history.undo(from: "ab") == "a")
        #expect(history.undo(from: "a") == nil)
        #expect(history.redo(from: "a") == "ab")
        #expect(history.redo(from: "ab") == "abc")
        #expect(history.redo(from: "abc") == nil)
    }

    @Test func undoRestoresEveryStepOfTypingAndRedoReplaysIt() async {
        let composer = await started()
        #expect(!composer.canUndo)
        composer.update(text: "a")
        composer.update(text: "ab")
        #expect(composer.canUndo)
        #expect(!composer.canRedo)
        composer.undo()
        #expect(composer.text == "a")
        #expect(composer.canRedo)
        composer.undo()
        #expect(composer.text == "")
        #expect(!composer.canUndo)
        composer.redo()
        composer.redo()
        #expect(composer.text == "ab")
        #expect(!composer.canRedo)
    }

    @Test func aSmileyAndAFormattingTagAreOneStepEach() async {
        let composer = await started("salut")
        _ = composer.insert(smiley: ":)", replacing: nil)
        let formatting = ComposerFormattingModel(composer: composer, clipboard: EmptyClipboard())
        formatting.selectedRange = NSRange(location: 0, length: 5)
        formatting.tap(.bbCode(.bold))
        #expect(composer.text.hasPrefix("[b]salut[/b]"))
        composer.undo()
        #expect(composer.text.hasPrefix("salut"))
        #expect(composer.text.contains(":)"))
        composer.undo()
        #expect(composer.text == "salut")
    }

    @Test func clearEmptiesTheTextAndUndoBringsItBack() async {
        let composer = await started("à garder")
        #expect(composer.canClear)
        composer.clearText()
        #expect(composer.text.isEmpty)
        #expect(!composer.canClear)
        composer.undo()
        #expect(composer.text == "à garder")
    }

    @Test func theOpeningTextIsNotAStep() async throws {
        // The draft is read into the text and the quote merged into it through `update(text:)`: neither is a step to undo.
        let drafts = HFRStorageDraftsFixture.store()
        try await drafts.save("Brouillon", for: replyTarget.draftContext, account: ComposerFixture.account)
        let composer = ReplyComposerModel(
            target: replyTarget, services: ComposerFixture.services(poster: ScriptedPoster([]), drafts: drafts),
            autosaveDelay: .seconds(60), quote: ReplyQuote(text: "[quotemsg=100,13,900001]Bonjour[/quotemsg]\n")
        )
        await composer.start()
        #expect(composer.text.hasPrefix("Brouillon"))
        #expect(composer.text.contains("[quotemsg=100"))
        #expect(!composer.canUndo)
    }

    @Test func undoSavesTheDraftLikeTyping() async {
        let drafts = HFRStorageDraftsFixture.store()
        let composer = ComposerFixture.model(poster: ScriptedPoster([]), drafts: drafts, autosaveDelay: .milliseconds(10))
        await composer.start()
        composer.update(text: "un")
        composer.update(text: "un deux")
        composer.undo()
        await composer.waitForAutosave()
        #expect(await ComposerFixture.storedText(drafts) == "un")
    }

    @Test func nothingActsWhileTheEditorIsLocked() async {
        let gate = ReaderGate()
        let composer = ComposerFixture.model(poster: ScriptedPoster([.success(replyConfirmed)], gate: gate))
        await composer.start()
        composer.update(text: "envoyé")
        let sending = Task { await composer.send() }
        await gate.untilArrived()
        #expect(!composer.canUndo)
        #expect(!composer.canClear)
        composer.undo()
        composer.clearText()
        #expect(composer.text == "envoyé")
        await gate.open()
        await sending.value
    }

    @Test func theRowMovesTheCaretToTheEndAfterUndoAndToTheStartAfterClear() async {
        let composer = await started("abc")
        composer.update(text: "abcdef")
        let formatting = ComposerFormattingModel(composer: composer, clipboard: EmptyClipboard())
        formatting.selectedRange = NSRange(location: 1, length: 0)
        let before = formatting.cursorRevision
        formatting.undo()
        #expect(composer.text == "abc")
        #expect(formatting.selectedRange == NSRange(location: 3, length: 0))
        #expect(formatting.cursorRevision == before + 1)
        formatting.redo()
        #expect(formatting.selectedRange == NSRange(location: 6, length: 0))
        formatting.clear()
        #expect(composer.text.isEmpty)
        #expect(formatting.selectedRange == NSRange(location: 0, length: 0))
    }

    @Test func aaShowsTheBarHiddenAtFirstAndHidingItClosesThePalette() async {
        let composer = await started()
        let formatting = ComposerFormattingModel(composer: composer, clipboard: EmptyClipboard())
        #expect(!formatting.isBarShown)
        formatting.toggleBar()
        #expect(formatting.isBarShown)
        formatting.isPaletteShown = true
        formatting.toggleBar()
        #expect(!formatting.isBarShown)
        #expect(!formatting.isPaletteShown)
    }
}

/// A clipboard with nothing in it: every tag goes in without a confirmation.
@MainActor
final class EmptyClipboard: ClipboardReading {
    var changeCount = 1
    var url: URL?
    var string: String?
}

/// A draft store in memory.
enum HFRStorageDraftsFixture {
    static func store() -> DraftStore { DraftStore(persistence: InMemoryDraftPersistence()) }
}
