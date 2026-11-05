import Foundation
import HFRClient
import HFRModels
import HFRStorage
import Observation

// Port of HFRswift/Swift/AnswerView.swift (AnswerView.postMessage, ComposerDraftPersistence) and HFRswift/Swift/ReplyService.swift
// (ForumReplyPostingService) @ 2440d79. Differences: draft per topic and account, autosaved, instead of one global draft (GAP-092, UXD);
// never resent after an uncertain send (GAP-100).
/// State of the composer sheet: a reply (LOT-084), a new private message (LOT-128, with a recipient and a subject) or a new topic
/// (LOT-089, with a subject and a sub-category read from the form); the
/// text, its draft, sending and the outcome.
///
/// The draft is the target's (`ComposerTarget.draftContext`) for the current account. It is restored when the sheet opens,
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
        /// The write may have been posted (`unconfirmed`): the reader shows the topic's last page, the Messages list reloads;
        /// the draft is kept when the store accepts it (not after `closeWithoutSaving`).
        case checkTopic
        /// Closed while the draft store refused writes: nothing was written, a stored draft is left as it was.
        case closedWithoutSaving
    }

    /// What is written: a reply to a topic, a new private message or a new topic.
    let target: ComposerTarget
    /// The text being written.
    private(set) var text = ""
    /// Recipient of a new private message: the link's `dest`, editable; empty for a reply.
    private(set) var recipient = ""
    /// Subject of a new private message, kept in its draft; empty for a reply.
    private(set) var subject = ""
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
    init(composing target: ComposerTarget, services: ComposerServices, autosaveDelay: Duration = .seconds(1)) {
        self.target = target
        self.services = services
        self.autosaveDelay = autosaveDelay
        if case .newPrivateMessage(let message) = target { recipient = message.recipient }
    }

    /// A reply composer for `target`.
    convenience init(target: ReplyTarget, services: ComposerServices, autosaveDelay: Duration = .seconds(1)) {
        self.init(composing: .reply(target), services: services, autosaveDelay: autosaveDelay)
    }

    /// The new-topic form's sub-category select (LOT-089): options, choice, loading and warning.
    private(set) var picker = NewTopicSubcategories()

    /// A new private message: the sheet shows the recipient and subject fields.
    var isNewMessage: Bool {
        if case .newPrivateMessage = target { true } else { false }
    }

    /// A new topic: the sheet shows the subject field and the sub-category picker.
    var isNewTopic: Bool {
        if case .newTopic = target { true } else { false }
    }

    /// The sheet shows a subject (a new private message or a new topic) and keeps it in the draft.
    var hasSubjectField: Bool { isNewMessage || isNewTopic }

    /// The text holds something to send.
    var hasText: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Send is offered (a new topic waits for its sub-category list, so HFR's default never overrides a choice):
    /// some text (and a subject for a new topic, a recipient and a subject for a new private message), the
    /// draft read, nothing running, not closed. HFR refuses an empty text (`W17a`); a blank recipient or subject is refused here
    /// and by the engine
    /// (HFR's answer to one is not captured).
    var canSend: Bool {
        guard hasText, canEdit, !(isNewTopic && picker.isLoading) else { return false }
        if isNewMessage { return !Self.isBlank(recipient) && !Self.isBlank(subject) }
        return !isNewTopic || !Self.isBlank(subject)
    }

    /// Closing asks whether to keep the draft (swiping the sheet down is blocked meanwhile, so it never loses the text).
    var closeNeedsChoice: Bool { hasText || !Self.isBlank(subject) }

    /// What the smiley picker needs: the favourites store and the account key.
    var smileyServices: (store: AppSmileyFavoritesStore, account: String) {
        (services.smileyFavorites, services.account)
    }

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
        if hasSubjectField { subject = draft?.subject ?? "" }
        isRestoring = false
        hasRestored = true
    }

    /// Reads the new-topic form's sub-category select; the sheet runs it beside `start()` so the editor never waits for the
    /// network (legacy loaded it when the sheet opened, `AnswerView.swift:625-640` @ 2440d79). A failure leaves the picker
    /// empty and the topic sendable: the engine then sends the form's own choice.
    func loadSubcategories() async {
        guard case .newTopic(let topic) = target, !picker.isLoading else { return }
        picker.beginLoading()
        do throws(PostingError) {
            picker.apply(try await services.poster.newTopicOptions(formURL: topic.formURL))
        } catch {
            picker.fail(ComposerMessages.subcategoriesUnavailable(error))
        }
    }

    /// The user chose a sub-category of the form's list.
    func select(subcategory value: String) {
        guard isNewTopic, canEdit, picker.select(value) else { return }
        // Choosing does not answer an uncertain send: its warning stays until the text or subject changes.
        if !mayHavePosted { errorMessage = nil }
    }

    /// The user typed: the draft is saved after a pause.
    func update(text newText: String) {
        guard canEdit, newText != text else { return }
        text = newText
        didEdit()
    }

    /// The user edited the subject of a new private message: saved with the text.
    func update(subject newSubject: String) {
        guard hasSubjectField, canEdit, newSubject != subject else { return }
        subject = newSubject
        didEdit()
    }

    /// The user edited the recipient of a new private message. Not part of the draft (LOT-063 keys it, stores no field).
    func update(recipient newRecipient: String) {
        guard isNewMessage, canEdit, newRecipient != recipient else { return }
        recipient = newRecipient
        errorMessage = nil
        mayHavePosted = false
    }

    private func didEdit() {
        errorMessage = nil
        mayHavePosted = false
        scheduleAutosave()
    }

    /// Inserts the smiley `code` over `selection` (the end of the text when nil), as legacy did (LOT-104). Returns the
    /// caret's UTF-16 offset in the new text, nil when the editor does not accept typing (nothing changed).
    func insert(smiley code: String, replacing selection: Range<String.Index>?) -> Int? {
        guard canEdit else { return nil }
        let result = SmileyInsertion.insert(code, into: text, replacing: selection)
        update(text: result.text)
        return result.caretUTF16Offset
    }

    /// Sends the reply or the new private message. Characters HFR would cut the message at are refused first (Q-3), in
    /// every field, with nothing requested.
    func send() async {
        guard canSend else { return }
        let refused = Self.unsupportedCharacters(in: hasSubjectField ? recipient + subject + text : text)
        guard refused.isEmpty else {
            errorMessage = ComposerMessages.unsupported(refused)
            return
        }
        isSending = true
        errorMessage = nil
        mayHavePosted = false
        // The exact text sent is on disk before the request leaves: a crash or an unconfirmed answer never loses it. A
        // failed write does not stop the send; the warning stays on screen.
        _ = await saveNow()
        do throws(PostingError) {
            let result = try await post()
            // The reply is posted: the sheet closes even if the draft cannot be deleted (spec, edge cases).
            _ = await discardDraft()
            isSending = false
            closeReason = .sent(result)
        } catch {
            isSending = false
            errorMessage = ComposerMessages.message(for: error, newMessage: isNewMessage, newTopic: isNewTopic)
            if case .unconfirmed = error { mayHavePosted = true }
            if case .unknownSubcategory = error, isNewTopic {
                // The list changed since it was read: every retry would fail the same way, so read it again.
                picker.reset()
                await loadSubcategories()
            }
        }
    }

    /// One write through the poster, with the fields as they are now. Recipient and subject are trimmed, as legacy Swift did
    /// (`AnswerView.swift:1474`, `MessagesView.swift:4213` @ 21173e77); a line break inside one is refused by the engine.
    private func post() async throws(PostingError) -> PostingResult {
        switch target {
        case .reply(let reply):
            return try await services.poster.reply(text, formURL: reply.formURL)
        case .newPrivateMessage(let message):
            return try await services.poster.newPrivateMessage(
                to: recipient.trimmingCharacters(in: .whitespacesAndNewlines),
                subject: subject.trimmingCharacters(in: .whitespacesAndNewlines),
                text: text, formURL: message.formURL
            )
        case .newTopic(let topic):
            return try await services.poster.newTopic(
                subject: subject.trimmingCharacters(in: .whitespacesAndNewlines), subcategory: picker.selected,
                text: text, formURL: topic.formURL
            )
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
    /// a later write replace a stored draft the editor never showed. After an unconfirmed send it closes as `.checkTopic`:
    /// the reply may be on the last page and the text is gone, so the reader must show it before the user types it again.
    func closeWithoutSaving() async {
        guard canCloseWithoutSaving else { return }
        isClosing = true
        await settleAutosave()
        closeReason = mayHavePosted ? .checkTopic : .closedWithoutSaving
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
            let kept = hasSubjectField && !Self.isBlank(subject) ? subject : nil
            try await services.drafts.save(hasText ? text : "", subject: kept, for: target.draftContext, account: services.account)
            draftWarning = nil
            return true
        } catch {
            draftWarning = Self.draftWarning(for: error)
            return false
        }
    }
}
