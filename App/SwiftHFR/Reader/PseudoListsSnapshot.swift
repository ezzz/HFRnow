import Foundation
import HFRModels
import HFRNetwork
import HFRStorage
import Synchronization

/// The account's blocklist and the allowlist, copied from the store so the reader can read them without waiting.
///
/// `PseudoListStore` is an actor and the reader builds its documents from a synchronous closure (`ReaderSettings`): this keeps
/// the last copy, and `RefreshingTopicPageSource` refreshes it before each page the reader loads, so a change made in Réglages
/// (LOT-118) shows on the next load, and `applyDisplaySettings()` rebuilds the shown page when the copy changes.
final class PseudoListsSnapshot: Sendable {
    private let store: PseudoListStore
    private let account: String?
    private let lists = Mutex(PseudoLists())

    /// A snapshot of `account`'s blocklist (nil logged out: only the allowlist) over `store`; empty until the first `refresh()`.
    init(store: PseudoListStore, account: String?) {
        self.store = store
        self.account = account
    }

    /// The single store of the app's pseudo lists (one actor per file), `Application Support/PseudoLists/lists.json`; LOT-118's
    /// editors and LOT-067's import write through it.
    static let liveStore = PseudoListStore(
        persistence: FilePseudoListPersistence(fileURL: URL.applicationSupportDirectory.appending(path: "PseudoLists/lists.json"))
    )

    /// The lists as of the last `refresh()`.
    var current: PseudoLists { lists.withLock { $0 } }

    /// Reads the store again. A store that cannot be read answers empty lists (it refuses writes, `PseudoListStore`).
    func refresh() async {
        var blocked: [PseudoListEntry] = []
        if let account { blocked = await store.blocklist(for: account) }
        let allowed = await store.allowlist()
        let updated = PseudoLists(blocklist: blocked.map(\.pseudo), allowlist: allowed.map(\.pseudo))
        lists.withLock { $0 = updated }
    }
}

/// A page source that refreshes the pseudo lists before every page it serves, so the document built from that page reads them.
struct RefreshingTopicPageSource: TopicPageSource {
    let base: any TopicPageSource
    let lists: PseudoListsSnapshot

    func page(for target: ReaderTarget) async throws(ListLoadError) -> ReaderPage {
        await lists.refresh()
        return try await base.page(for: target)
    }
}
