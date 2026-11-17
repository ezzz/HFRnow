import Foundation
import HFRStorage
import Synchronization

/// The held blocklist changes of one account, shared by every window of the app (LOT-146 builds one session environment per
/// window, each with its own `BlocklistChangeLog`): a removal held in one window must stop another window's merge from
/// importing the pseudo back.
final class HeldBlocklistChanges: Sendable {
    /// The held changes, oldest first.
    let changes = Mutex<[BlocklistChange]>([])

    private static let registry = Mutex<[String: HeldBlocklistChanges]>([:])

    /// The app's one list for `account` (by `AccountKey`).
    static func shared(for account: String) -> HeldBlocklistChanges {
        registry.withLock { lists in
            let key = AccountKey.make(account)
            if let list = lists[key] { return list }
            let list = HeldBlocklistChanges()
            lists[key] = list
            return list
        }
    }
}

/// The blocklist changes made on this device that the account's MPStorage document may not carry yet (LOT-131), shared by
/// the writer (`PseudoListManager`, any isolation) and the reader (`BlocklistSyncModel`, main actor).
///
/// A change is recorded **before** the local write, so a reconciliation running at the same time never takes a pseudo the
/// user just removed for a remote addition; a write that fails or changes nothing withdraws it. The held changes are the
/// account's, across windows (`HeldBlocklistChanges`); the stream is this window's. Memory only: after a relaunch the
/// reconciliation's union carries additions, and a removal not yet written can come back (spec, Edge cases).
final class BlocklistChangeLog: Sendable {
    private let held: HeldBlocklistChanges
    private let continuation: AsyncStream<BlocklistChange>.Continuation
    /// The recorded changes, in order, for the one consumer (`BlocklistSyncModel.run()`).
    let changes: AsyncStream<BlocklistChange>

    /// A log over `held` (a fresh list by default: tests and previews; the app passes the account's shared one).
    init(held: HeldBlocklistChanges = HeldBlocklistChanges()) {
        self.held = held
        (changes, continuation) = AsyncStream.makeStream(of: BlocklistChange.self)
    }

    /// The changes not yet known to be in the document, oldest first.
    var pending: [BlocklistChange] { held.changes.withLock { $0 } }

    /// Holds `change` before its local write.
    func hold(_ change: BlocklistChange) {
        held.changes.withLock { $0.append(change) }
    }

    /// The local write of `change` is done: the consumer is told. `changed` false (no-op or failure) withdraws it.
    func finish(_ change: BlocklistChange, changed: Bool) {
        guard changed else {
            withdraw([change])
            return
        }
        continuation.yield(change)
    }

    /// Forgets `changes` (one occurrence each, the oldest first): the document carries them, or the account does not sync.
    func withdraw(_ changes: [BlocklistChange]) {
        held.changes.withLock { list in
            for change in changes {
                if let index = list.firstIndex(of: change) { list.remove(at: index) }
            }
        }
    }
}
