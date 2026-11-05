import Foundation
import Observation

/// The pasteboard as the formatting model reads it; the app's one is `SystemClipboard`, tests script it.
@MainActor
protocol ClipboardReading {
    /// Bumps every time the pasteboard content changes.
    var changeCount: Int { get }
    /// The pasteboard URL, if any.
    var url: URL? { get }
    /// The pasteboard text, if any.
    var string: String? { get }
}

// Port of HFRswift/Swift/AnswerView.swift (performFormatting, PendingClipboardInsertion, clipboard*Candidate)
// @ origin/master 21173e7. Differences: a model instead of view @State, the pasteboard behind `ClipboardReading`.
/// State of the formatting toolbar (LOT-085): the caret, the colour palette and the clipboard confirmation.
///
/// It edits the text of a `ReplyComposerModel` through `ReplyTextInsertionEngine` and always says where the caret goes
/// (`cursorRevision` changes on every edit), so the editor never jumps to the end.
@MainActor
@Observable
final class ComposerFormattingModel {
    /// A confirmation waiting for the user: the clipboard holds something the tap could use.
    enum Pending: Equatable {
        case link(url: String, range: NSRange, changeCount: Int)
        case formatting(text: String, target: ReplyFormattingTarget, range: NSRange, changeCount: Int)

        /// The alert's message (French).
        var message: String {
            switch self {
            case .link(let url, _, _): url
            case .formatting(let text, let target, _, _):
                "Insérer « \(ComposerFormattingModel.preview(text)) » avec \(target.label) ?"
            }
        }
    }

    /// The caret or selection, UTF-16; kept in step with the editor by the view.
    var selectedRange = NSRange(location: 0, length: 0)
    /// Changes whenever an edit sets `selectedRange`: the view moves the editor's caret then.
    private(set) var cursorRevision = 0
    /// The palette replaces the tag buttons.
    var isPaletteShown = false
    /// The clipboard alert, when one is open.
    private(set) var pending: Pending?

    private let composer: ReplyComposerModel
    private let clipboard: any ClipboardReading
    /// A clipboard content already inserted or refused is not offered again (legacy `insertedClipboardChangeCount`).
    private var usedChangeCount: Int?

    /// A toolbar model editing `composer`'s text.
    init(composer: ReplyComposerModel, clipboard: any ClipboardReading) {
        self.composer = composer
        self.clipboard = clipboard
    }

    /// A toolbar button was tapped.
    func tap(_ target: ReplyFormattingTarget) {
        guard composer.canEdit else { return }
        let range = ReplyTextInsertionEngine.clamped(selectedRange, in: composer.text)
        if case .bbCode(.url) = target, range.length > 0, let candidate = urlCandidate() {
            pending = .link(url: candidate.text, range: range, changeCount: candidate.changeCount)
            return
        }
        if range.length == 0, let candidate = textCandidate() {
            pending = .formatting(text: candidate.text, target: target, range: range, changeCount: candidate.changeCount)
            return
        }
        apply(target, range: range)
    }

    /// The user accepted the clipboard (Oui / Insérer).
    func acceptPending() {
        guard let current = pending else { return }
        pending = nil
        switch current {
        case .link(let url, let range, let changeCount):
            usedChangeCount = changeCount
            commit(ReplyTextInsertionEngine.wrapSelectionWithURL(url, in: composer.text, selectedUTF16Range: range))
        case .formatting(let text, let target, let range, let changeCount):
            usedChangeCount = changeCount
            apply(target, range: range, clipboardText: text)
        }
    }

    /// The user refused the clipboard (Non / Sans le presse-papiers): the plain tags go in.
    func declinePending() {
        guard let current = pending else { return }
        pending = nil
        switch current {
        case .link(_, let range, _): apply(.bbCode(.url), range: range)
        case .formatting(_, let target, let range, _): apply(target, range: range)
        }
    }

    /// The alert was dismissed without a choice: nothing is inserted.
    func dismissPending() { pending = nil }

    /// Inserts `snippet` (a smiley code) at the caret.
    func insert(_ snippet: String) {
        guard composer.canEdit else { return }
        commit(ReplyTextInsertionEngine.insert(snippet, into: composer.text, selectedUTF16Range: selectedRange))
    }

    /// Splits the quote around the caret; false when the caret is not inside one.
    @discardableResult
    func splitQuoteAtCaret() -> Bool {
        guard composer.canEdit,
              let result = ReplyTextInsertionEngine.splitQuote(in: composer.text, atUTF16Offset: selectedRange.location)
        else { return false }
        commit(result)
        return true
    }

    private func apply(_ target: ReplyFormattingTarget, range: NSRange, clipboardText: String? = nil) {
        commit(ReplyTextInsertionEngine.wrapWithBBCode(
            rawTag: target.rawTag, in: composer.text, selectedUTF16Range: range, textForEmptySelection: clipboardText
        ))
        isPaletteShown = false
    }

    private func commit(_ result: ReplyTextInsertionResult) {
        composer.update(text: result.text)
        selectedRange = NSRange(location: result.cursorLocationUTF16, length: 0)
        cursorRevision += 1
    }

    private func textCandidate() -> (text: String, changeCount: Int)? {
        let count = clipboard.changeCount
        guard count != usedChangeCount, let text = clipboard.string,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return (text, count)
    }

    private func urlCandidate() -> (text: String, changeCount: Int)? {
        let count = clipboard.changeCount
        guard count != usedChangeCount else { return nil }
        if let url = clipboard.url, Self.isHTTP(url) { return (url.absoluteString, count) }
        guard let string = clipboard.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              let url = URL(string: string), Self.isHTTP(url) else { return nil }
        return (string, count)
    }

    private static func isHTTP(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    /// One line, at most 140 characters, as the legacy alert shows it.
    nonisolated static func preview(_ text: String) -> String {
        let line = text.replacing("\r\n", with: " ").replacing("\n", with: " ").replacing("\r", with: " ")
        return line.count > 140 ? String(line.prefix(140)) + "…" : line
    }
}
