import Foundation
import HFRClient
import HFRStorage
import Observation

/// State of the reply sheet (LOT-084): the text, its draft, sending and the outcome.
///
/// The draft is the topic's (`ReplyTarget.draftContext`) for the current account. It is restored when the sheet opens,
/// saved while typing (debounced, through the same `persist` as every other save, LESSONS 48), kept or discarded on
/// close as the user chooses, and discarded only after HFR confirmed the reply. Any other outcome keeps the text and
/// says what happened.
@MainActor
@Observable
final class ReplyComposerModel: Identifiable {
    /// Why the sheet closes; the reader reacts to it.
    enum CloseReason: Equatable, Sendable {
        /// HFR confirmed the reply; the draft is gone.
        case sent(PostingResult)
        /// Closed with the text kept as the topic's draft.
        case keptDraft
        /// Closed with the draft deleted.
        case discardedDraft
        /// The reply may have been posted (`unconfirmed`): the draft is kept and the reader shows the topic's last page.
        case checkTopic
        /// Closed while the draft store refused writes: nothing was written, a stored draft is left as it was.
        case closedWithoutSaving
    }

    /// The topic the reply goes to.
    let target: ReplyTarget
    /// The text being written.
    private(set) var text = ""
    /// The stored draft is being read; the editor waits for it, so typing never races the restore.
    private(set) var isRestoring = false
    /// A reply is being sent.
    private(set) var isSending = false
    /// Why the last send failed, in French; nil when there is nothing to report.
    private(set) var errorMessage: String?
    /// The last send may have been posted: the sheet offers to check the topic.
    private(set) var mayHavePosted = false
    /// The draft could not be read or written; the text on screen is still there.
    private(set) var draftWarning: String?
    /// Set once the sheet must close.
    private(set) var closeReason: CloseReason?
    /// Cancel was tapped with text: the sheet asks whether to keep the draft.
    var isAskingClose = false

    /// Unique per sheet.
    nonisolated var id: ObjectIdentifier { ObjectIdentifier(self) }

    private let services: ComposerServices
    private let autosaveDelay: Duration
    private var hasRestored = false
    /// A close was asked and is writing the draft; typing would schedule a save that outlives the choice.
    private var isClosing = false
    private var autosave: Task<Void, Never>?

    /// A composer for `target`; nothing is read before `start()`. `autosaveDelay` debounces draft writes (LOT-063: every
    /// save rewrites the file).
    init(target: ReplyTarget, services: ComposerServices, autosaveDelay: Duration = .seconds(1)) {
        self.target = target
        self.services = services
        self.autosaveDelay = autosaveDelay
    }

    /// The text holds something to send.
    var hasText: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Send is offered: some text, the draft read, nothing running, not closed.
    var canSend: Bool { hasText && canEdit }

    /// Closing asks whether to keep the draft (swiping the sheet down is blocked meanwhile, so it never loses the text).
    var closeNeedsChoice: Bool { hasText }

    /// The editor accepts typing.
    var canEdit: Bool { hasRestored && !isSending && !isClosing && closeReason == nil }

    /// The draft store refused a write or cannot be read (`draftWarning`): keep, discard and Cancel on an emptied text all
    /// write, so the sheet offers this exit instead of trapping the user.
    var canCloseWithoutSaving: Bool { draftWarning != nil && closeReason == nil && !isSending && !isClosing }

    /// Reads the topic's draft once; the editor shows it.
    func start() async {
        guard !hasRestored, !isRestoring else { return }
        isRestoring = true
        let drafts = services.drafts
        let account = services.account
        let context = target.draftContext
        let draft = await drafts.draft(for: context, account: account)
        if let failure = await drafts.loadFailure() {
            draftWarning = Self.draftWarning(for: failure)
        }
        text = draft?.text ?? ""
        isRestoring = false
        hasRestored = true
    }

    /// The user typed: the draft is saved after a pause.
    func update(text newText: String) {
        guard canEdit, newText != text else { return }
        text = newText
        errorMessage = nil
        mayHavePosted = false
        scheduleAutosave()
    }

    /// Sends the reply. Characters HFR would cut the message at are refused first (Q-3), with nothing requested.
    func send() async {
        guard canSend else { return }
        let refused = Self.unsupportedCharacters(in: text)
        guard refused.isEmpty else {
            errorMessage = ComposerMessages.unsupported(refused)
            return
        }
        isSending = true
        errorMessage = nil
        mayHavePosted = false
        let sending = text
        // The exact text sent is on disk before the request leaves: a crash or an unconfirmed answer never loses it. A
        // failed write does not stop the send; the warning stays on screen.
        _ = await saveNow()
        do throws(PostingError) {
            let result = try await services.poster.reply(sending, formURL: target.formURL)
            // The reply is posted: the sheet closes even if the draft cannot be deleted (spec, edge cases).
            _ = await discardDraft()
            isSending = false
            closeReason = .sent(result)
        } catch {
            isSending = false
            errorMessage = ComposerMessages.message(for: error)
            if case .unconfirmed = error { mayHavePosted = true }
        }
    }

    /// Cancel: asks keep or discard when there is text; with none, deletes the draft (an emptied text means no draft) and
    /// closes. Before the draft was read nothing is written, so a stored draft is never lost unseen.
    func requestClose() async {
        guard closeReason == nil, !isSending, !isClosing else { return }
        if !hasRestored {
            closeReason = .keptDraft
        } else if closeNeedsChoice {
            isAskingClose = true
        } else {
            await discardDraftAndClose()
        }
    }

    /// Closes and keeps the text as the topic's draft. When the draft cannot be written the sheet stays open with the
    /// warning and its `closeWithoutSaving` exit: closing here would lose the text the user chose to keep.
    func keepDraftAndClose() async {
        guard closeReason == nil, !isSending, !isClosing else { return }
        isClosing = true
        guard await saveNow() else {
            isClosing = false
            return
        }
        closeReason = .keptDraft
    }

    /// Closes and deletes the topic's draft. When it cannot be deleted the sheet stays open with the warning and its
    /// `closeWithoutSaving` exit: closing here would bring back the draft the user deleted at the next reply.
    func discardDraftAndClose() async {
        guard closeReason == nil, !isSending, !isClosing else { return }
        isClosing = true
        guard await discardDraft() else {
            isClosing = false
            return
        }
        closeReason = .discardedDraft
    }

    /// Closes without writing the draft, as the warning says, while the store refuses writes. The pending autosave is
    /// cancelled, so nothing is written after the choice. The store is not reloaded: a read that works again would let
    /// a later write replace a stored draft the editor never showed.
    func closeWithoutSaving() async {
        guard canCloseWithoutSaving else { return }
        isClosing = true
        await settleAutosave()
        closeReason = .closedWithoutSaving
    }

    /// After an unconfirmed send: closes with the draft kept, so the user can look at the topic before sending again.
    /// Stays open, like `keepDraftAndClose`, when the draft cannot be written.
    func checkTopic() async {
        guard mayHavePosted, closeReason == nil, !isSending, !isClosing else { return }
        isClosing = true
        guard await saveNow() else {
            isClosing = false
            return
        }
        closeReason = .checkTopic
    }

    /// Writes the pending draft now (the app goes to the background, the sheet goes away without a choice). Does nothing
    /// before the draft was read, which would overwrite it, nor once the sheet closed, which already decided.
    func flushDraft() async {
        guard canEdit else { return }
        await settleAutosave()
        // A send or a close may have started while this flush waited: their own writes decide, this one must not land
        // after them.
        guard canEdit else { return }
        _ = await persist()
    }

    /// Waits for the scheduled autosave (tests).
    func waitForAutosave() async {
        await autosave?.value
    }

    // MARK: - Draft writes

    /// Each autosave waits for the one it replaces: a replaced save that already woke up still finishes first, so waiting
    /// for the latest one (`settleAutosave`) waits for every write in flight.
    private func scheduleAutosave() {
        let previous = autosave
        previous?.cancel()
        let delay = autosaveDelay
        autosave = Task { [weak self] in
            await previous?.value
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            // Only narrows the window: `settleAutosave` awaiting the chain is what orders this write before a discard.
            guard !Task.isCancelled else { return }
            _ = await self?.persist()
        }
    }

    /// Cancels the pending autosave and waits for a write already running, then saves the text. Returns whether it was
    /// written.
    private func saveNow() async -> Bool {
        await settleAutosave()
        return await persist()
    }

    /// Cancels the pending autosave and waits for a write already running, then deletes the draft. Waiting matters: a
    /// save landing after the discard would bring the draft back.
    private func discardDraft() async -> Bool {
        await settleAutosave()
        do {
            try await services.drafts.discard(for: target.draftContext, account: services.account)
            return true
        } catch {
            draftWarning = Self.draftWarning(for: error)
            return false
        }
    }

    private func settleAutosave() async {
        let pending = autosave
        autosave = nil
        pending?.cancel()
        await pending?.value
    }

    /// The one write path of the draft. Blank text removes it (LOT-063 removes an empty one): a whitespace-only draft
    /// would come back in an editor that looks empty. Returns whether the write succeeded.
    private func persist() async -> Bool {
        do {
            try await services.drafts.save(hasText ? text : "", for: target.draftContext, account: services.account)
            draftWarning = nil
            return true
        } catch {
            draftWarning = Self.draftWarning(for: error)
            return false
        }
    }

    // MARK: - Rules

    /// Distinct characters with a scalar above U+FFFF, in order: HFR cuts the message at the first one (Q-3, `W12`).
    static func unsupportedCharacters(in text: String) -> [Character] {
        var refused: [Character] = []
        for character in text where character.unicodeScalars.contains(where: { $0.value > 0xFFFF }) {
            if !refused.contains(character) { refused.append(character) }
        }
        return refused
    }

    private static func draftWarning(for error: any Error) -> String {
        if case .loadFailed = error as? DraftError {
            return "Les brouillons sont illisibles pour le moment : ce texte ne sera pas sauvegardé si vous fermez."
        }
        return "Le brouillon n’a pas pu être enregistré. Le texte reste affiché ; copiez-le si vous fermez."
    }
}
