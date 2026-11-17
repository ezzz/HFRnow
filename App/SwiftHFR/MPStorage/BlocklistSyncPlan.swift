import Foundation
import HFRModels
import HFRStorage

/// A blocklist change made on this device that the MPStorage document may not carry yet (LOT-131).
struct BlocklistChange: Sendable, Hashable {
    /// The pseudo as the user wrote it, cleaned (`PseudoNormalizer.cleaned`).
    let pseudo: String
    /// True for an addition, false for a removal.
    let added: Bool

    /// The key both lists compare on (`PseudoNormalizer.comparisonForm`).
    var key: String { PseudoNormalizer.comparisonForm(pseudo) }
}

// Port of Classes/MPStorage.m (updateBlackList:) @ 87fe0d1c. Differences: the remote list is merged into the local one
// instead of replacing it (ADR 0013 §2, audit Q-4), so an empty or broken remote list never empties the device's; local
// entries the document lacks are written to it (legacy's reload dropped them).
/// What one reconciliation of the account's blocklist with its MPStorage document does (LOT-131). Pure: the model applies it.
///
/// Rules, on the comparison form of each pseudo (LOT-072):
/// - **Remote additions** (in the document, not on the device) are added on the device, unless the device holds a removal
///   the document does not carry yet.
/// - **Remote removals** (in the document read before, gone from the one read now) are removed on the device, only when
///   the document read now still lists something or carries a tombstone for that pseudo: an emptied list is never taken
///   as "remove everything" (E-2, the legacy wipe).
/// - **Local entries** the document lacks, and that were not just removed remotely, are written to the document; so are
///   the device's removals the document does not carry yet.
struct BlocklistSyncPlan: Equatable, Sendable {
    /// Pseudos to add on the device, as the document writes them.
    var addLocally: [String] = []
    /// Pseudos to remove from the device, as the device writes them.
    var removeLocally: [String] = []
    /// Pseudos to add to the document, as the device writes them.
    var addRemotely: [String] = []
    /// Document usernames to remove, exactly as the document writes them (every case variant of a removed pseudo).
    var removeRemotely: [String] = []

    /// Nothing to do on either side.
    var isEmpty: Bool { addLocally.isEmpty && removeLocally.isEmpty && addRemotely.isEmpty && removeRemotely.isEmpty }

    /// Nothing to write to the document.
    var writesRemotely: Bool { !addRemotely.isEmpty || !removeRemotely.isEmpty }

    /// The plan for the device's `local` list, the document read `before` this sync (nil when none was ever read), the one
    /// read `after` it, and the device's `held` changes the document may not carry yet.
    static func make(
        local: [String], before: MPStorageDocument?, after: MPStorageDocument, held: [BlocklistChange]
    ) -> BlocklistSyncPlan {
        let remote = usernames(in: after)
        let remoteKeys = Set(remote.map(PseudoNormalizer.comparisonForm))
        let localKeys = Set(local.map(PseudoNormalizer.comparisonForm))
        // The last held change of a pseudo wins (an add then a remove is a remove).
        var heldByKey: [String: Bool] = [:]
        for change in held where !change.key.isEmpty { heldByKey[change.key] = change.added }
        let heldRemovals = Set(heldByKey.filter { !$0.value }.keys)
        let heldAdditions = Set(heldByKey.filter { $0.value }.keys)

        var plan = BlocklistSyncPlan()
        let removedRemotely = remoteRemovals(before: before, after: after, remoteKeys: remoteKeys).subtracting(heldAdditions)
        for pseudo in local where removedRemotely.contains(PseudoNormalizer.comparisonForm(pseudo)) {
            plan.removeLocally.append(pseudo)
        }
        var seen = Set<String>()
        for name in remote {
            let key = PseudoNormalizer.comparisonForm(name)
            guard !key.isEmpty, !localKeys.contains(key), !heldRemovals.contains(key), seen.insert(key).inserted else { continue }
            plan.addLocally.append(name)
        }
        seen = []
        for pseudo in local {
            let key = PseudoNormalizer.comparisonForm(pseudo)
            guard !key.isEmpty, !remoteKeys.contains(key), !removedRemotely.contains(key), !heldRemovals.contains(key),
                  seen.insert(key).inserted else { continue }
            plan.addRemotely.append(pseudo)
        }
        plan.removeRemotely = remote.filter { heldRemovals.contains(PseudoNormalizer.comparisonForm($0)) }
        return plan
    }

    /// The usernames of the document's writable entry (`0.1`, the one LOT-062 edits), in its order; empty without one.
    static func usernames(in document: MPStorageDocument) -> [String] {
        guard let index = document.writableEntryIndex else { return [] }
        return document.data[index].blocklist?.list.map(\.username) ?? []
    }

    /// Keys listed `before` and gone `after`, kept only when `after` still lists something or holds a tombstone for them.
    private static func remoteRemovals(before: MPStorageDocument?, after: MPStorageDocument, remoteKeys: Set<String>) -> Set<String> {
        guard let before else { return [] }
        let gone = Set(usernames(in: before).map(PseudoNormalizer.comparisonForm)).subtracting(remoteKeys)
        guard !remoteKeys.isEmpty else {
            let index = after.writableEntryIndex
            let tombstones = index.flatMap { after.data[$0].blocklist?.tombstones } ?? []
            return gone.intersection(tombstones.map { PseudoNormalizer.comparisonForm($0.id) })
        }
        return gone
    }

    /// Whether `document` already carries `change`: the pseudo listed for an addition, absent for a removal.
    static func carries(_ change: BlocklistChange, in document: MPStorageDocument) -> Bool {
        let listed = usernames(in: document).contains { PseudoNormalizer.comparisonForm($0) == change.key }
        return listed == change.added
    }

    /// Applies the document side of the plan to `document`; returns whether it changed. A pseudo the forum cannot store
    /// (a character outside the BMP, LOT-062) is skipped and stays on the device only; a document without a writable entry
    /// is refused as a whole.
    static func apply(
        adding: [String], removing: [String], to document: inout MPStorageDocument, stamp: MPStorageStamp
    ) throws -> Bool {
        var changed = false
        for name in removing {
            changed = try document.removeBlocklistEntry(username: name, stamp: stamp) || changed
        }
        // Inserted at the top one by one: reversed, the document keeps the device's order.
        for pseudo in adding.reversed() {
            do {
                changed = try document.addBlocklistEntry(username: pseudo, stamp: stamp) || changed
            } catch MPStorageError.noWritableEntry {
                throw MPStorageError.noWritableEntry
            } catch {
                continue
            }
        }
        return changed
    }
}
