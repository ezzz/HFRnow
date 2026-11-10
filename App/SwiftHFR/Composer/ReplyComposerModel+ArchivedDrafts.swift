import Foundation
import HFRModels
import HFRStorage

// Port of HFRswift/Swift/AnswerView.swift (useDraft, archiveAndClearCurrentDraft, clearTopicDrafts, removeDraft, :693-760) @ 87fe0d1c.
// Differences: stored per account in the draft store (LOT-063) instead of one `UserDefaults` list for every account; a write that
// fails is reported and changes nothing on screen; no in-sheet undo of the swap (the text it replaces is archived first); a quote
// merges into the draft (LOT-086), so it never replaces one and archives nothing (GAP-093).
extension ReplyComposerModel {
    /// The topic whose archive this sheet shows; only a reply has one (legacy: `draftContext != nil`, `AnswerView.swift:783`).
    var archiveTopic: TopicID? {
        if case .reply(let reply) = target { reply.topic } else { nil }
    }

    /// The picker is offered.
    var offersArchivedDrafts: Bool { archiveTopic != nil }

    /// "Mettre de côté et vider" is possible: there is text to set aside.
    var canArchiveCurrent: Bool { offersArchivedDrafts && hasText && canEdit }

    /// Reads the topic's archive again; an unreadable store shows an empty list (the warning is the draft's own).
    func refreshArchivedDrafts() async {
        guard let topic = archiveTopic else { return }
        archivedDrafts = await services.drafts.archivedReplies(topic: topic, account: services.account)
    }

    /// Sets the text aside and empties the editor ("Mettre de côté et vider"). Nothing changes when the archive cannot be written.
    func archiveAndClear() async {
        guard canArchiveCurrent, let topic = archiveTopic else { return }
        isMovingDrafts = true
        defer { isMovingDrafts = false }
        await settleAutosave()
        do {
            try await services.drafts.archiveReply(text, topic: topic, source: draftSource, account: services.account)
        } catch {
            draftWarning = Self.draftWarning(for: error)
            return
        }
        replaceText(with: "")
        draftSource = .quickReply
        pickedArchivedID = nil
        // Blank text removes the topic's active draft.
        _ = await persist()
        await refreshArchivedDrafts()
    }

    /// Puts an archived draft in the editor. A different text already there is set aside first, then the picked one is set aside
    /// again as the newest (legacy `useDraft`); it stays in the archive until the reply is posted.
    func use(_ draft: ArchivedDraft) async {
        guard canEdit, let topic = archiveTopic else { return }
        isMovingDrafts = true
        defer { isMovingDrafts = false }
        await settleAutosave()
        var picked = draft
        let current = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !current.isEmpty, current != draft.text.trimmingCharacters(in: .whitespacesAndNewlines) {
            do {
                try await services.drafts.archiveReply(text, topic: topic, source: draftSource, account: services.account)
                picked = try await services.drafts.archiveReply(draft.text, topic: topic, source: draft.source, account: services.account)
                    ?? draft
            } catch {
                draftWarning = Self.draftWarning(for: error)
                await refreshArchivedDrafts()
                return
            }
        }
        replaceText(with: draft.text)
        draftSource = draft.source
        pickedArchivedID = picked.id
        _ = await persist()
        await refreshArchivedDrafts()
    }

    /// Deletes one archived draft (swipe "Supprimer").
    func discardArchived(_ draft: ArchivedDraft) async {
        guard let topic = archiveTopic else { return }
        do {
            try await services.drafts.discardArchivedReply(id: draft.id, topic: topic, account: services.account)
            if pickedArchivedID == draft.id { pickedArchivedID = nil }
        } catch {
            draftWarning = Self.draftWarning(for: error)
        }
        await refreshArchivedDrafts()
    }

    /// Deletes every archived draft of the topic ("Vider").
    func discardAllArchived() async {
        guard let topic = archiveTopic else { return }
        do {
            try await services.drafts.discardArchivedReplies(topic: topic, account: services.account)
            pickedArchivedID = nil
        } catch {
            draftWarning = Self.draftWarning(for: error)
        }
        await refreshArchivedDrafts()
    }

    /// After HFR confirmed the reply: the archived draft it came from is done with (legacy `AnswerView.swift:1509`). A failure
    /// leaves it in the list, where the user can delete it; the reply is posted either way.
    func releasePickedArchivedDraft() async {
        guard let id = pickedArchivedID, let topic = archiveTopic else { return }
        pickedArchivedID = nil
        _ = try? await services.drafts.discardArchivedReply(id: id, topic: topic, account: services.account)
    }
}
