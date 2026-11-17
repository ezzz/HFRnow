import Foundation
import Synchronization

/// The blocklist changes made on this device that the account's MPStorage document may not carry yet (LOT-131), shared by
/// the writer (`PseudoListManager`, any isolation) and the reader (`BlocklistSyncModel`, main actor).
///
/// A change is recorded **before** the local write, so a reconciliation running at the same time never takes a pseudo the
/// user just removed for a remote addition; a write that fails or changes nothing withdraws it. Memory only: after a
/// relaunch the reconciliation's union carries additions, and a removal not yet written can come back (spec, Edge cases).
final class BlocklistChangeLog: Sendable {
    private let held = Mutex<[BlocklistChange]>([])
    private let continuation: AsyncStream<BlocklistChange>.Continuation
    /// The recorded changes, in order, for the one consumer (`BlocklistSyncModel.run()`).
    let changes: AsyncStream<BlocklistChange>

    /// An empty log.
    init() {
        (changes, continuation) = AsyncStream.makeStream(of: BlocklistChange.self)
    }

    /// The changes not yet known to be in the document, oldest first.
    var pending: [BlocklistChange] { held.withLock { $0 } }

    /// Holds `change` before its local write.
    func hold(_ change: BlocklistChange) {
        held.withLock { $0.append(change) }
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
        held.withLock { list in
            for change in changes {
                if let index = list.firstIndex(of: change) { list.remove(at: index) }
            }
        }
    }
}
