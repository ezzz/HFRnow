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
    /// A pick or an answer is running (reading the document, switching on): a second pick waits, and the reader keeps this
    /// model, so the prompt it ends with is shown.
    private(set) var isWorking = false

    @ObservationIgnored private let mpStorage: MPStorageSyncModel?
    @ObservationIgnored private let confirm: @MainActor (String) -> Void

    /// Bookmarks through `mpStorage` (nil logged out and in the saved-copy reader: no entry); `confirm` shows the outcome.
    init(mpStorage: MPStorageSyncModel?, confirm: @escaping @MainActor (String) -> Void) {
        self.mpStorage = mpStorage
        self.confirm = confirm
    }

    /// Nothing is asked: the model can be replaced by one with fresher services.
    var isIdle: Bool { prompt == nil && pendingConsent == nil && !isWorking }

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
        isWorking = true
        defer { isWorking = false }
        guard let draft = Draft(context) else {
            confirm("Données bookmark incomplètes")
            return
        }
        switch mpStorage.writeConsent(for: .bookmarks) {
        case .sync: await offer(draft)
        case .ask: pendingConsent = draft
        case .deviceOnly: confirm(Self.notSyncing)
        }
    }

    /// What a pick says when the account does not sync its bookmarks (declined, off, decided in another window).
    static let notSyncing = "Activez le stockage MP dans Réglages pour créer un bookmark."

    /// The consent answer for `draft` (SwiftUI clears the alert's state before the button runs, AGENTS.md LOT-087). Yes switches
    /// the account on (an existing thread is read, a missing one leads to the creation question at the root) and, once on, asks
    /// the title; no records nothing: bookmarks have no device-only list to keep.
    func answerConsent(_ accept: Bool, for draft: Draft) async {
        pendingConsent = nil
        guard accept, let mpStorage else { return }
        isWorking = true
        defer { isWorking = false }
        mpStorage.reloadRecord()
        // Another window (LOT-146) may have decided meanwhile: an `off` or `declined` there stands.
        if mpStorage.record?.state == .unasked { await mpStorage.setEnabled(true, from: .write) }
        switch mpStorage.writeConsent(for: .bookmarks) {
        case .sync: await offer(draft)
        // The creation question is on screen (the root): the member picks « Bookmark » again once the thread exists.
        case .ask where mpStorage.asksCreation: break
        // Offline, logged out, the search at its limit: say why nothing happened (the reader never shows the sync's status).
        case .ask: confirm(Self.failure(of: mpStorage) ?? "Le stockage MP n'a pas pu être activé.")
        case .deviceOnly: confirm(Self.notSyncing)
        }
    }

    /// Why `title` cannot be a bookmark's title, nil when it can: empty text for a blank title (legacy `:492`, nothing to
    /// say), the sentence for a character outside the Basic Multilingual Plane (most emoji), which HFR cuts the storage message
    /// at (LOT-062 refuses it, HFR-PROTOCOL §6, Q-3).
    static func titleProblem(_ title: String) -> String? {
        let label = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if label.isEmpty { return "" }
        guard label.unicodeScalars.allSatisfy({ $0.value <= 0xFFFF }) else {
            return "Les emoji ne peuvent pas être enregistrés dans le stockage MP."
        }
        return nil
    }

    /// Creates the bookmark of `draft` titled `title` (trimmed); a title `titleProblem` refuses creates nothing.
    func create(_ draft: Draft, title: String) async {
        prompt = nil
        guard Self.titleProblem(title) == nil, let mpStorage else { return }
        let bookmark = draft.bookmark(label: title.trimmingCharacters(in: .whitespacesAndNewlines))
        let changed = await mpStorage.edit(.bookmarks) { document, stamp in try document.addBookmark(bookmark, stamp: stamp) }
        if changed {
            // Local first (GAP-183): the edit stays pending when its write failed; LOT-130's sentence says what follows.
            confirm(Self.failure(of: mpStorage).map { "Bookmark créé sur cet appareil. \($0)" } ?? "Bookmark créé")
        } else if BookmarkList.contains(bookmark.id, in: mpStorage.document(for: .bookmarks)) {
            confirm("Post déjà dans les bookmarks")
        } else if mpStorage.writeConsent(for: .bookmarks) != .sync {
            confirm(Self.notSyncing)
        } else {
            confirm(Self.failure(of: mpStorage) ?? "Erreur à la création du bookmark")
        }
    }

    /// LOT-130's sentence for the call that just ended, nil when it succeeded (no pseudo, no document text).
    private static func failure(of mpStorage: MPStorageSyncModel) -> String? {
        guard case .failed(let message) = mpStorage.status else { return nil }
        return message
    }

    /// The title prompt, unless the message is already bookmarked. The device copy is shown first; a document never read on
    /// this device is read from the forum: LOT-130's edit refuses to write before it.
    private func offer(_ draft: Draft) async {
        guard let mpStorage else { return }
        await mpStorage.loadCopyIfNeeded()
        if mpStorage.document(for: .bookmarks) == nil { await mpStorage.resync() }
        // Still nothing read (offline, logged out): the edit would be refused, so no prompt.
        guard mpStorage.document(for: .bookmarks) != nil else {
            confirm(Self.failure(of: mpStorage) ?? MPStorageSyncModel.message(for: .notLoaded))
            return
        }
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
