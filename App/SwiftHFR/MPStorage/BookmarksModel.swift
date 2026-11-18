import Foundation
import HFRModels
import Observation

// Port of HFRswift/Swift/BookmarksPlusView.swift (BookmarksPlusViewModel) and Classes/MPStorage.m (parseBookmarks,
// removeBookmarkSynchronous:) @ 87fe0d1c. Differences: the list is the device copy of the document (readable offline, pending
// edits included) instead of a fresh forum read; a removal is written locally first and sent by LOT-130's sync (GAP-183);
// it removes that category, topic and message (legacy removed the last entry with the same message number). GAP-040.
/// Plus › Bookmarks (LOT-132): the bookmarks of the current account's MPStorage document, refreshed, opened and deleted.
@MainActor
@Observable
final class BookmarksModel {
    /// What the screen shows instead of, or above, the list.
    enum State: Equatable {
        /// No account: no MPStorage.
        case signedOut
        /// The account does not sync its bookmarks (legacy « Stockage MP désactivé »).
        case notSyncing
        /// The account syncs: the list (possibly empty).
        case syncing
    }

    /// The bookmark last opened, selected in the list while it shows beside it (legacy `bookmarksTopicTarget`).
    private(set) var selectedID: String?

    @ObservationIgnored private let mpStorage: MPStorageSyncModel?

    /// The bookmarks of `mpStorage`'s account; nil logged out.
    init(mpStorage: MPStorageSyncModel?) {
        self.mpStorage = mpStorage
    }

    /// The screen's state.
    var state: State {
        guard let mpStorage else { return .signedOut }
        return mpStorage.isOn && mpStorage.isEnabled(.bookmarks) ? .syncing : .notSyncing
    }

    /// The list, newest first; empty unless the account syncs its bookmarks.
    var bookmarks: [MPStorageBookmark] { BookmarkList.bookmarks(in: mpStorage?.document(for: .bookmarks)) }

    /// A call of the account's sync is running.
    var isRefreshing: Bool { mpStorage?.status == .working }

    /// LOT-130's sentence for the last failed call, nil when the last call succeeded (no pseudo, no document text).
    var errorMessage: String? {
        guard state == .syncing, case .failed(let message)? = mpStorage?.status else { return nil }
        return message
    }

    /// Appearance: shows the device copy and syncs it, once per session model (the Messages tab's `start`).
    func load() async {
        await mpStorage?.start()
    }

    /// « Actualiser » and pull to refresh: reads the forum and writes the pending edits (only while the account syncs).
    func refresh() async {
        await mpStorage?.resync()
    }

    /// Records the row the user opened.
    func didOpen(_ bookmark: MPStorageBookmark) {
        selectedID = bookmark.id
    }

    /// Removes `bookmark` from the document; returns whether it was the one open beside the list (the caller closes it).
    @discardableResult
    func delete(_ bookmark: MPStorageBookmark) async -> Bool {
        guard let mpStorage else { return false }
        let id = bookmark.id
        await mpStorage.edit(.bookmarks) { document, stamp in try document.removeBookmark(id: id, stamp: stamp) }
        guard selectedID == id else { return false }
        selectedID = nil
        return true
    }
}
