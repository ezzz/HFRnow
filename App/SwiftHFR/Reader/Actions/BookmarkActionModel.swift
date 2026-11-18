import Foundation
import HFRModels
import Observation

// Port of HFRswift/Swift/MessagesView.swift (askBookmarkPrompt `:4545-4566`, the bookmark sheet `:5475-5496`) and
// Classes/MPStorage.m (addBookmarkSynchronous: `:313-357`) @ 87fe0d1c. Differences: the bookmark is written in the device copy
// first and sent by LOT-130's sync, so a forum failure no longer refuses it (GAP-183); an account that never chose is asked
// first instead of the entry being hidden (ADR 0013 §7); a bookmark is the category, topic and message, not the message number
// alone. GAP-068.
/// « Bookmark » in the message menu (LOT-132): bookmarks the message in the account's MPStorage document, after a title
/// prompt. One per reader; the session's `MPStorageSyncModel` holds the document.
@MainActor
@Observable
final class BookmarkActionModel {
    /// The message a bookmark is being created for.
    struct Draft: Equatable, Identifiable {
        let topic: TopicID
        let numreponse: Int
        let author: String

        var id: String { bookmark(label: "").id }

        /// The bookmark this draft makes with `label`.
        func bookmark(label: String) -> MPStorageBookmark {
            MPStorageBookmark(
                topic: topic.topic, category: topic.category.queryValue, numreponse: numreponse, author: author, label: label
            )
        }
    }

    /// The question of a first bookmark when the account never chose (ADR 0013 §7).
    static let consentQuestion = "Enregistrer les bookmarks de ce compte dans le stockage MP (un message privé sur le forum) ?"

    /// The draft whose title is asked (the sheet).
    var prompt: Draft?
    /// The draft waiting for the consent answer (the alert).
    var pendingConsent: Draft?

    @ObservationIgnored private let mpStorage: MPStorageSyncModel?
    @ObservationIgnored private let confirm: @MainActor (String) -> Void

    /// Bookmarks through `mpStorage` (nil logged out and in the saved-copy reader: no entry); `confirm` shows the outcome.
    init(mpStorage: MPStorageSyncModel?, confirm: @escaping @MainActor (String) -> Void) {
        self.mpStorage = mpStorage
        self.confirm = confirm
    }

    /// Nothing is asked: the model can be replaced by one with fresher services.
    var isIdle: Bool { prompt == nil && pendingConsent == nil }

    /// The menu entry.
    var handler: any MessageActionHandler {
        WriteActionHandler(
            kind: .bookmark,
            canRun: { [weak self] in self?.canBookmark($0) ?? false },
            run: { [weak self] context in await self?.start(context) }
        )
    }

    /// Whether « Bookmark » is offered (legacy `canBookmark`, `ObjCMessageActionsBuilder.m:18`): a public topic and an account
    /// whose bookmarks sync or that never chose. Read as the record stands: the menu is being built, nothing is reloaded.
    func canBookmark(_ context: MessageMenuContext) -> Bool {
        guard let mpStorage, Draft(context) != nil, mpStorage.isEnabled(.bookmarks) else { return false }
        switch mpStorage.record?.state {
        case .on?, .unasked?: return true
        case .declined?, .off?, nil: return false
        }
    }

    /// The picked entry: the title prompt while the account syncs, the consent question when it never chose.
    func start(_ context: MessageMenuContext) async {
        guard let mpStorage, isIdle else { return }
        guard let draft = Draft(context) else {
            confirm("Données bookmark incomplètes")
            return
        }
        switch mpStorage.writeConsent(for: .bookmarks) {
        case .sync: await offer(draft)
        case .ask: pendingConsent = draft
        case .deviceOnly: confirm("Activez le stockage MP dans Réglages pour créer un bookmark.")
        }
    }

    /// The consent answer for `draft` (SwiftUI clears the alert's state before the button runs, AGENTS.md LOT-087). Yes switches
    /// the account on (an existing thread is read, a missing one leads to the creation question at the root) and, once on, asks
    /// the title; no records nothing: bookmarks have no device-only list to keep.
    func answerConsent(_ accept: Bool, for draft: Draft) async {
        pendingConsent = nil
        guard accept, let mpStorage else { return }
        mpStorage.reloadRecord()
        // Another window (LOT-146) may have decided meanwhile: an `off` or `declined` there stands.
        if mpStorage.record?.state == .unasked { await mpStorage.setEnabled(true, from: .write) }
        if mpStorage.writeConsent(for: .bookmarks) == .sync { await offer(draft) }
    }

    /// Creates the bookmark of `draft` titled `title` (trimmed; an empty one creates nothing, legacy `:492`).
    func create(_ draft: Draft, title: String) async {
        prompt = nil
        let label = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty, let mpStorage else { return }
        let bookmark = draft.bookmark(label: label)
        let changed = await mpStorage.edit(.bookmarks) { document, stamp in try document.addBookmark(bookmark, stamp: stamp) }
        if changed {
            // Local first (GAP-183): the edit stays pending when its write failed, and goes at the next sync.
            if case .failed = mpStorage.status {
                confirm("Bookmark créé ; il sera écrit sur le forum à la prochaine synchronisation.")
            } else {
                confirm("Bookmark créé")
            }
        } else if BookmarkList.contains(bookmark.id, in: mpStorage.document(for: .bookmarks)) {
            confirm("Post déjà dans les bookmarks")
        } else {
            confirm("Erreur à la création du bookmark")
        }
    }

    /// The title prompt, unless the message is already bookmarked. The device copy is shown first; a document never read on
    /// this device is read from the forum: LOT-130's edit refuses to write before it.
    private func offer(_ draft: Draft) async {
        guard let mpStorage else { return }
        await mpStorage.loadCopyIfNeeded()
        if mpStorage.document(for: .bookmarks) == nil { await mpStorage.resync() }
        guard !BookmarkList.contains(draft.id, in: mpStorage.document(for: .bookmarks)) else {
            confirm("Post déjà dans les bookmarks")
            return
        }
        prompt = draft
    }
}

extension BookmarkActionModel.Draft {
    /// The draft of `context`'s message; nil without a public topic or a message number (legacy « Données bookmark
    /// incomplètes »; a private message is never bookmarked, `ObjCMessageActionsBuilder.m:17-18`).
    init?(_ context: MessageMenuContext) {
        guard let topic = context.topic, case .forum = topic.category, topic.topic > 0, context.numreponse > 0 else { return nil }
        self.init(topic: topic, numreponse: context.numreponse, author: context.author)
    }
}
