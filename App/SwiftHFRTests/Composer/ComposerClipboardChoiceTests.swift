import Foundation
@testable import SwiftHFR
import Testing

@MainActor
private final class ScriptedClipboard: ClipboardReading {
    var changeCount = 1
    var url: URL?
    var string: String?
}

/// #1180 (HIG: choices in a dialog with verb titles, and a real « Annuler » that backs out). Legacy `AnswerView.swift:530-557` @ 87fe0d1c
/// answered « Non » / « Oui » and its cancel button still inserted the tag: a deliberate difference.
@MainActor
struct ComposerClipboardChoiceTests {
    private func pending(_ kind: String) -> ComposerFormattingModel.Pending {
        let range = NSRange(location: 0, length: 0)
        switch kind {
        case "link": return .link(url: "https://example.org", range: NSRange(location: 0, length: 1), changeCount: 1)
        case "linkChoice": return .linkChoice(text: "https://example.org", range: range, changeCount: 1)
        default: return .formatting(text: "texte", target: .bbCode(.bold), range: range, changeCount: 1)
        }
    }

    private func titles(_ kind: String) -> [String] { pending(kind).choices.map(\.title) }

    @Test(arguments: ["link", "linkChoice", "formatting"])
    func everyQuestionEndsWithACancelThatIsNotAnAnswer(kind: String) {
        let choices = pending(kind).choices
        #expect(choices.last?.kind == .cancel)
        #expect(choices.last?.title == "Annuler")
        #expect(choices.filter { $0.kind == .cancel }.count == 1)
    }

    @Test(arguments: ["link", "linkChoice", "formatting"])
    func noTitleIsAPlainYesOrNo(kind: String) {
        #expect(!titles(kind).contains { $0.hasPrefix("Oui") || $0 == "Non" })
    }

    @Test func eachQuestionNamesItsActions() {
        #expect(titles("link") == ["Coller le lien", "Insérer sans le presse-papiers", "Annuler"])
        #expect(titles("linkChoice") == ["Insérer [url=XXX]", "Insérer [url]XXX[/url]", "Insérer sans le presse-papiers", "Annuler"])
        #expect(titles("formatting") == ["Insérer", "Insérer sans le presse-papiers", "Annuler"])
    }

    private func model(selecting length: Int) async -> (ReplyComposerModel, ComposerFormattingModel) {
        let clipboard = ScriptedClipboard()
        clipboard.string = "https://example.org"
        clipboard.url = URL(string: "https://example.org")
        let composer = ComposerFixture.model(poster: ScriptedPoster([]))
        await composer.start()
        composer.update(text: "mot")
        let formatting = ComposerFormattingModel(composer: composer, clipboard: clipboard)
        formatting.selectedRange = NSRange(location: 0, length: length)
        return (composer, formatting)
    }

    @Test func cancellingInsertsNothingAndLeavesTheTextAlone() async throws {
        let (composer, formatting) = await model(selecting: 0)
        formatting.tap(.bbCode(.bold))
        let pending = try #require(formatting.pending)
        let cancel = try #require(pending.choices.first { $0.kind == .cancel })
        formatting.choose(cancel, for: pending)
        #expect(formatting.pending == nil)
        #expect(composer.text == "mot")
    }

    @Test func theClipboardlessChoiceInsertsThePlainTags() async throws {
        let (composer, formatting) = await model(selecting: 3)
        formatting.tap(.bbCode(.url))
        let pending = try #require(formatting.pending)
        formatting.choose(try #require(pending.choices.first { $0.kind == .withoutClipboard }), for: pending)
        #expect(composer.text == "[url]mot[/url]")
    }

    @Test func theFirstChoiceUsesTheClipboard() async throws {
        let (composer, formatting) = await model(selecting: 3)
        formatting.tap(.bbCode(.url))
        let pending = try #require(formatting.pending)
        formatting.choose(try #require(pending.choices.first), for: pending)
        #expect(composer.text == "[url=https://example.org]mot[/url]")
    }
}
