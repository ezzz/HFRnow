import Foundation
import HFRModels
import HFRStorage
import Observation

// Port of Classes/BlackList.m (addToBlackList:andSave:, removeFromBlackList:andSave:) and Classes/MPStorage.m
// (updateBlackList:, addBlackListSynchronous:, removeBlackListSynchronous:) @ 87fe0d1c. Differences: the device list is
// written first and the document after (legacy wrote the forum first and gave up the local change on any failure); a remote
// load merges instead of replacing (an empty remote list never empties the device's); the first write of an account that
// never chose asks before syncing (ADR 0013 §7). GAP-182.
/// The blocklist of the current account kept in step with its MPStorage document (LOT-131). One per account session, next to
/// `MPStorageSyncModel`: each local change goes to the document while the account syncs, and each successful sync merges the
/// document into the device's list (`BlocklistSyncPlan`).
@MainActor
@Observable
final class BlocklistSyncModel {
    /// The question of the first blocklist write when the account never chose (ADR 0013 §7).
    static let consentQuestion = "Synchroniser la liste noire de ce compte avec le stockage MP (un message privé sur le forum) ?"

    /// True while the consent question waits for an answer.
    var asksConsent = false

    /// The account's MPStorage sync.
    let mpStorage: MPStorageSyncModel
    @ObservationIgnored private let store: PseudoListStore
    @ObservationIgnored private let changes: BlocklistChangeLog
    @ObservationIgnored private let refreshLists: @Sendable () async -> Void
    /// True while a reconciliation runs: the sync its own write triggers does not start a second one inside it.
    @ObservationIgnored private var reconciling = false

    /// The model of `mpStorage`'s account over the device's lists; `refreshLists` refreshes the reader's copy after a change.
    init(
        mpStorage: MPStorageSyncModel, store: PseudoListStore, changes: BlocklistChangeLog,
        refreshLists: @escaping @Sendable () async -> Void
    ) {
        self.mpStorage = mpStorage
        self.store = store
        self.changes = changes
        self.refreshLists = refreshLists
        mpStorage.afterSync = { [weak self] before, after in await self?.reconcile(before: before, after: after) }
    }

    /// Takes the device's changes in order, for the session's lifetime (the root's `.task`).
    func run() async {
        for await change in changes.changes {
            await handle(change)
        }
    }

    /// One local change, already written on the device: written to the document while the account syncs, else the consent
    /// question when the account never chose, else nothing (the list stays on the device).
    func handle(_ change: BlocklistChange) async {
        switch mpStorage.writeConsent(for: .ignoreList) {
        case .sync:
            await mpStorage.edit(.ignoreList) { document, stamp in
                try BlocklistSyncPlan.apply(
                    adding: change.added ? [change.pseudo] : [],
                    removing: change.added ? [] : Self.names(of: change, in: document), to: &document, stamp: stamp
                )
            }
            releaseCarried()
        case .ask:
            asksConsent = true
        case .deviceOnly:
            changes.withdraw([change])
        }
    }

    /// The answer to the consent question. Yes switches the account on (`MPStorageSyncModel.setEnabled`): an existing
    /// thread is synced and merged at once, a missing one leads to the creation question. No records `declined` for this
    /// account only; the list stays on the device.
    func answerConsent(_ accept: Bool) async {
        asksConsent = false
        guard accept else {
            await mpStorage.answerCreation(false)
            changes.withdraw(changes.pending)
            return
        }
        await mpStorage.setEnabled(true, from: .write)
    }

    /// Merges the document read by a successful sync into the device's list, then writes to the document what only the
    /// device has (`BlocklistSyncPlan`). Nothing happens while the function is off, or while the device's list cannot be read
    /// (an unreadable list reads empty: E-2).
    func reconcile(before: MPStorageDocument?, after: MPStorageDocument) async {
        guard !reconciling, mpStorage.document(for: .ignoreList) != nil else { return }
        guard await store.loadFailure() == nil else { return }
        reconciling = true
        defer { reconciling = false }
        let local = await store.blocklist(for: mpStorage.account).map(\.pseudo)
        let plan = BlocklistSyncPlan.make(local: local, before: before, after: after, held: changes.pending)
        guard !plan.isEmpty else {
            releaseCarried()
            return
        }
        var changedLocally = false
        for pseudo in plan.removeLocally {
            changedLocally = ((try? await store.unblock(pseudo, account: mpStorage.account)) ?? false) || changedLocally
        }
        for pseudo in plan.addLocally {
            changedLocally = ((try? await store.block(pseudo, account: mpStorage.account)) ?? false) || changedLocally
        }
        if changedLocally { await refreshLists() }
        if plan.writesRemotely {
            let adding = plan.addRemotely, removing = plan.removeRemotely
            await mpStorage.edit(.ignoreList) { document, stamp in
                try BlocklistSyncPlan.apply(adding: adding, removing: removing, to: &document, stamp: stamp)
            }
        }
        releaseCarried()
    }

    /// Forgets the held changes the document shown now carries (pending local edits included: they are written at the next
    /// sync whatever happens, LOT-130).
    private func releaseCarried() {
        guard let document = mpStorage.document(for: .ignoreList) else { return }
        changes.withdraw(changes.pending.filter { BlocklistSyncPlan.carries($0, in: document) })
    }

    /// Every username of `document` that is `change`'s pseudo, as the document writes it (case variants included).
    nonisolated private static func names(of change: BlocklistChange, in document: MPStorageDocument) -> [String] {
        BlocklistSyncPlan.usernames(in: document).filter { PseudoNormalizer.comparisonForm($0) == change.key }
    }
}
