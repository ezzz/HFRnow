import Foundation
import HFRClient
import HFRStorage

/// The sync loop's copy (HFRClient) kept in the device store (HFRStorage) under one account (LOT-130).
struct MPStorageCopyPersistence: MPStorageSyncPersistence {
    let store: MPStorageCopyStore
    /// `md_user` of the account, as the app stores it.
    let account: String

    /// The app's one store of device copies: device-only, never backed up to iCloud KVS (ADR 0013 appendix B).
    static let liveStore = MPStorageCopyStore(
        persistence: FileSmallStorePersistence(fileURL: URL.applicationSupportDirectory.appending(path: "MPStorage/copies.json"))
    )

    func load() async throws(MPStorageSyncError) -> MPStorageSyncCopy {
        guard let copy = await store.copy(for: account) else {
            let failure = await store.loadFailure()
            throw .storage(reason: failure.map { String(describing: $0) } ?? "unreadable")
        }
        return MPStorageSyncCopy(
            post: copy.post, base: copy.base, pending: copy.pending, lastSync: copy.lastSync, lastSearch: copy.lastSearch
        )
    }

    func save(_ copy: MPStorageSyncCopy) async throws(MPStorageSyncError) {
        do {
            try await store.save(
                MPStorageCopy(
                    post: copy.post, base: copy.base, pending: copy.pending, lastSync: copy.lastSync, lastSearch: copy.lastSearch
                ),
                for: account
            )
        } catch {
            throw .storage(reason: String(describing: error))
        }
    }
}
