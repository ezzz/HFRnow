import Foundation
@testable import SwiftHFR
import Testing

@MainActor
private final class FakeClipboard: ClipboardReading {
    var changeCount = 1
    var url: URL?
    var string: String?
}

@MainActor
private func accept(_ model: ComposerFormattingModel) {
    if let pending = model.pending { model.acceptPending(pending) }
}

@MainActor
private func decline(_ model: ComposerFormattingModel) {
    if let pending = model.pending { model.declinePending(pending) }
}

/// The toolbar model: edits through the composer, the caret request, the clipboard confirmations (HFR-010).
@MainActor
struct ComposerFormattingModelTests {
    private func make(_ text: String, clipboard: FakeClipboard = FakeClipboard()) async -> (ReplyComposerModel, ComposerFormattingModel) {
        let composer = ComposerFixture.model(poster: ScriptedPoster([]))
        await composer.start()
        composer.update(text: text)
        return (composer, ComposerFormattingModel(composer: composer, clipboard: clipboard))
    }

    @Test func aTagWrapsTheSelectionAndRequestsTheCaret() async {
        let (composer, formatting) = await make("un deux trois")
        formatting.selectedRange = NSRange(location: 3, length: 4)
        let before = formatting.cursorRevision
        formatting.tap(.bbCode(.bold))
        #expect(composer.text == "un [b]deux[/b] trois")
        #expect(formatting.selectedRange == NSRange(location: 14, length: 0))
        #expect(formatting.cursorRevision == before + 1)
    }

    @Test func theCaretStaysWhereTheEditHappened() async {
        let (_, formatting) = await make("début fin")
        formatting.selectedRange = NSRange(location: 5, length: 0)
        formatting.tap(.bbCode(.italic))
        #expect(formatting.selectedRange.location == 8)
    }

    @Test func aColourClosesThePalette() async {
        let (composer, formatting) = await make("a")
        formatting.isPaletteShown = true
        formatting.selectedRange = NSRange(location: 0, length: 1)
        formatting.tap(.color(ReplyTextColor.palette[4]))
        #expect(composer.text == "[#ff0000]a[/#ff0000]")
        #expect(!formatting.isPaletteShown)
    }

    @Test func linkWithClipboardUrlAsksThenWrapsWithTheAddress() async {
        let clipboard = FakeClipboard()
        clipboard.string = " https://example.org/page "
        let (composer, formatting) = await make("voir ici", clipboard: clipboard)
        formatting.selectedRange = NSRange(location: 5, length: 3)
        formatting.tap(.bbCode(.url))
        #expect(composer.text == "voir ici")
        #expect(formatting.pending == .link(url: "https://example.org/page", range: NSRange(location: 5, length: 3), changeCount: 1))
    }

    @Test func acceptingTheClipboardLinkWritesItAndIsNotOfferedAgain() async {
        let clipboard = FakeClipboard()
        clipboard.url = URL(string: "https://example.org/")
        let (composer, _) = await make("voir ici")
        let model = ComposerFormattingModel(composer: composer, clipboard: clipboard)
        model.selectedRange = NSRange(location: 5, length: 3)
        model.tap(.bbCode(.url))
        accept(model)
        #expect(composer.text == "voir [url=https://example.org/]ici[/url]")
        model.selectedRange = NSRange(location: 0, length: 4)
        model.tap(.bbCode(.url))
        #expect(model.pending == nil)
        #expect(composer.text.hasPrefix("[url]voir[/url]"))
    }

    @Test func decliningTheLinkWritesPlainTags() async {
        let clipboard = FakeClipboard()
        clipboard.url = URL(string: "https://example.org/")
        let (composer, _) = await make("ici")
        let model = ComposerFormattingModel(composer: composer, clipboard: clipboard)
        model.selectedRange = NSRange(location: 0, length: 3)
        model.tap(.bbCode(.url))
        decline(model)
        #expect(composer.text == "[url]ici[/url]")
    }

    @Test func nonHTTPClipboardIsNotALink() async {
        let clipboard = FakeClipboard()
        clipboard.string = "javascript:alert(1)"
        let (composer, _) = await make("ici")
        let model = ComposerFormattingModel(composer: composer, clipboard: clipboard)
        model.selectedRange = NSRange(location: 0, length: 3)
        model.tap(.bbCode(.url))
        #expect(model.pending == nil)
        #expect(composer.text == "[url]ici[/url]")
    }

    @Test func clipboardTextIsOfferedForAnEmptySelectionAndWrapped() async {
        let clipboard = FakeClipboard()
        clipboard.string = "extrait\nsur deux lignes"
        let (composer, _) = await make("x")
        let model = ComposerFormattingModel(composer: composer, clipboard: clipboard)
        model.selectedRange = NSRange(location: 1, length: 0)
        model.tap(.bbCode(.quote))
        #expect(model.pending?.message == "Insérer « extrait sur deux lignes » avec Citation ?")
        accept(model)
        #expect(composer.text == "x[quote]extrait\nsur deux lignes[/quote]")
        #expect(model.selectedRange.location == composer.text.utf16.count)
    }

    @Test func aNewClipboardIsOfferedAgain() async {
        let clipboard = FakeClipboard()
        clipboard.string = "a"
        let (composer, _) = await make("")
        let model = ComposerFormattingModel(composer: composer, clipboard: clipboard)
        model.tap(.bbCode(.bold))
        accept(model)
        model.tap(.bbCode(.bold))
        #expect(model.pending == nil)
        clipboard.changeCount += 1
        model.tap(.bbCode(.bold))
        #expect(model.pending != nil)
    }

    @Test func dismissingTheAlertInsertsNothing() async {
        let clipboard = FakeClipboard()
        clipboard.string = "a"
        let (composer, _) = await make("")
        let model = ComposerFormattingModel(composer: composer, clipboard: clipboard)
        model.tap(.bbCode(.bold))
        model.dismissPending()
        #expect(model.pending == nil)
        #expect(composer.text.isEmpty)
    }

    @Test func nothingHappensWhileTheComposerCannotEdit() async {
        let composer = ComposerFixture.model(poster: ScriptedPoster([]))
        let clipboard = FakeClipboard()
        clipboard.string = "a"
        let model = ComposerFormattingModel(composer: composer, clipboard: clipboard)
        model.tap(.bbCode(.bold))
        #expect(model.pending == nil)
        #expect(model.cursorRevision == 0)
        #expect(!model.isEnabled)
    }

    @Test func decliningDoesNotMarkTheClipboardUsed() async {
        let clipboard = FakeClipboard()
        clipboard.string = "a"
        let (_, model) = await make("", clipboard: clipboard)
        model.tap(.bbCode(.bold))
        decline(model)
        model.tap(.bbCode(.bold))
        #expect(model.pending != nil)
    }

    @Test func theCaretGoesToTheEndAfterARestore() async {
        let (composer, model) = await make("abc")
        model.placeCaretAtEnd()
        #expect(model.selectedRange == NSRange(location: 3, length: 0))
        model.tap(.bbCode(.bold))
        #expect(composer.text == "abc[b][/b]")
    }

    @Test func aColourTapClosesThePaletteEvenWithAClipboardAlert() async {
        let clipboard = FakeClipboard()
        clipboard.string = "a"
        let (_, model) = await make("", clipboard: clipboard)
        model.isPaletteShown = true
        model.tap(.color(ReplyTextColor.palette[0]))
        #expect(model.pending != nil)
        #expect(!model.isPaletteShown)
    }

    @Test func splitQuoteWorksFromTheCaret() async {
        let (composer, formatting) = await make("[quotemsg=1]abcd[/quotemsg]")
        formatting.selectedRange = NSRange(location: 14, length: 0)
        #expect(formatting.splitQuoteAtCaret())
        #expect(composer.text == "[quotemsg=1]ab[/quotemsg]\n\n\n[quotemsg=1]cd[/quotemsg]")
        #expect(!formatting.splitQuoteAtCaret())
    }
}
