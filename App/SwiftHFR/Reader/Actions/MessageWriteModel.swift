import Foundation
import HFRClient
import HFRModels
import Observation

// Port of HFRswift/Swift/MessagesView.swift (`openEditComposer`, `prefillComposer`, `askDeleteMessageConfirmation`, `confirmDeleteMessage`,
// `:3525-3576`, `:3805-3836`, alerts `:4618-4640`) and HFRswift/Swift/ReplyService.swift (`ForumMessageDeletionService`, `:922-1040`)
// @ 2440d79. Differences: GAP-096, GAP-097 (the (a) half, first post out: LOT-175, UXD-14); the reader reloads the page on screen and a
// delete HFR did not confirm says so instead of "Message supprimé" (GAP-100).
/// "Editer" and "Supprimer" of the message menu (LOT-088): opens the composer on the message's edit form, asks before deleting, and
/// tells the reader what HFR confirmed. Nothing is sent twice: a failed or unconfirmed delete only says so.
@MainActor
@Observable
final class MessageWriteModel {
    /// A failure to show. `retry` is the edit form to read again: reading is safe, and a write is never offered again here.
    struct Failure: Equatable, Identifiable {
        let id = UUID()
        let title: String
        let message: String
        var retry: EditTarget?
    }

    /// The edit composer on screen.
    var editor: ReplyComposerModel?
    /// The message the delete confirmation is about.
    var pendingDelete: EditTarget?
    /// What the alert says.
    var failure: Failure?
    /// What is being read or sent, as shown above the page; nil when nothing runs.
    private(set) var progress: String?

    private weak var reader: TopicReaderModel?
    private let services: ComposerServices

    /// Writes on the messages of `reader` through the current account's `services`.
    init(reader: TopicReaderModel, services: ComposerServices) {
        self.reader = reader
        self.services = services
    }

    /// The target of `context`, read from the reader's page; nil unless the page and the edit link agree.
    private func target(of context: MessageMenuContext) -> EditTarget? {
        EditTarget(link: context.actions.editURL, post: context.numreponse, topic: reader?.page?.topicID)
    }

    /// The menu entries: each needs a usable edit link, and "Supprimer" what the policy says (never on the first post).
    var handlers: [any MessageActionHandler] {
        [
            WriteActionHandler(kind: .edit, canRun: { [weak self] in self?.target(of: $0) != nil }, run: { [weak self] context in
                if let target = self?.target(of: context) { await self?.openEditor(target) }
            }),
            WriteActionHandler(
                kind: .delete, canRun: { [weak self] in $0.canDelete && self?.target(of: $0) != nil },
                run: { [weak self] context in
                    if let target = self?.target(of: context) { self?.askDelete(target) }
                }
            )
        ]
    }

    /// "Editer": reads the edit form, then opens the composer on it. A failure opens nothing and offers to read it again.
    func openEditor(_ target: EditTarget) async {
        guard progress == nil, editor == nil else { return }
        progress = "Chargement de l’édition…"
        defer { progress = nil }
        do throws(PostingError) {
            let prefill = try await services.poster.editPrefill(target)
            editor = ReplyComposerModel(editing: target, prefill: prefill, services: services)
        } catch {
            failure = Failure(title: "Edition impossible", message: ComposerMessages.editUnavailable(error), retry: target)
        }
    }

    /// The composer closed: HFR's sentence and the message after a confirmed edit, the message alone after an unconfirmed one,
    /// so the user sees what the forum holds. Closing with or without the draft changes nothing.
    func editorDidClose(_ reason: ReplyComposerModel.CloseReason, post: Int) async {
        switch reason {
        case .sent(let result):
            reader?.showConfirmation(result.message)
            await reader?.reloadPage(at: post)
        case .checkTopic:
            await reader?.reloadPage(at: post)
        case .keptDraft, .discardedDraft, .closedWithoutSaving:
            break
        }
    }

    /// "Supprimer": asks first (legacy alert, `MessagesView.swift:4628-4635`).
    func askDelete(_ target: EditTarget) {
        guard progress == nil else { return }
        pendingDelete = target
    }

    /// The user confirmed. Only HFR's own sentence counts as deleted; an unconfirmed delete reloads the page, so the user sees
    /// whether the message is gone, and is never sent again.
    func confirmDelete(_ target: EditTarget) async {
        pendingDelete = nil
        guard progress == nil else { return }
        progress = "Suppression du message…"
        defer { progress = nil }
        do throws(PostingError) {
            let result = try await services.poster.delete(target)
            reader?.showConfirmation(result.message)
            await reader?.reloadPage(at: nil)
        } catch {
            failure = Failure(title: "Suppression impossible", message: ComposerMessages.deletion(error))
            if case .unconfirmed = error { await reader?.reloadPage(at: nil) }
        }
    }
}

/// One entry of the message menu backed by `MessageWriteModel`.
@MainActor
struct WriteActionHandler: MessageActionHandler {
    let kind: MessageMenuAction.Kind
    /// Whether the entry applies to the message.
    let canRun: @MainActor (MessageMenuContext) -> Bool
    /// Runs the entry.
    let run: @MainActor (MessageMenuContext) async -> Void

    func isAvailable(for context: MessageMenuContext) -> Bool { canRun(context) }

    func perform(with context: MessageMenuContext) async { await run(context) }
}
