import Foundation
import HFRModels

/// The images uploaded to the image host from this device, to insert them again later (LOT-064).
///
/// Legacy kept them in `Documents/rehostImagesSwiftUI.json` (`ReplyService.swift:1895-1920`): each upload inserted at
/// the top (`AnswerView.swift:656`), a swipe removed one by identity (`AnswerView.swift:1909`), no limit. This store
/// keeps those rules with `RehostedImage.id` as the identity, and adds nothing twice. A removal is remembered (the newest
/// `RehostUploadHistoryDocument.removalsLimit`), so the iCloud merge of #966 does not bring the image back.
public actor RehostUploadHistoryStore {
    private var state: SmallStoreState<RehostUploadHistoryDocument>
    private var feed = ChangeFeed()
    private let clock: @Sendable () -> Date

    /// Creates a store over `persistence`; nothing is read until the first call. `clock` dates the removals.
    public init(
        persistence: any SmallStorePersistence<RehostUploadHistoryDocument>,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        state = SmallStoreState(persistence: persistence)
        self.clock = clock
    }

    /// The uploaded images, the last one added first; empty while the stored data is unreadable.
    public func images() -> [RehostedImage] {
        state.document()?.images ?? []
    }

    /// The whole document (uploads and removals); nil while the stored data is unreadable.
    public func document() -> RehostUploadHistoryDocument? {
        state.document()
    }

    /// A signal after each saved change, for the iCloud sync (LOT-172, #966).
    public func changes() -> AsyncStream<Void> {
        feed.stream()
    }

    /// The reason writes are refused, or nil when the store is usable (loading it if needed).
    public func loadFailure() -> SmallStoreError? {
        state.failure()
    }

    /// Adds an uploaded image at the top. Returns false when an image with the same `id` is already there.
    @discardableResult
    public func add(_ image: RehostedImage) throws(SmallStoreError) -> Bool {
        try saved(state.mutate { document in
            guard !document.images.contains(where: { $0.id == image.id }) else { return false }
            document.images.insert(image, at: 0)
            return true
        })
    }

    /// Removes every image whose `RehostedImage.id` is `id`, as legacy's swipe did (`AnswerView.swift:1909`), and
    /// remembers the removal. Returns false when there was none.
    @discardableResult
    public func remove(id: String) throws(SmallStoreError) -> Bool {
        let now = clock()
        return try saved(state.mutate { document in
            let count = document.images.count
            document.images.removeAll { $0.id == id }
            guard document.images.count != count else { return false }
            document = document.merging(images: [], removals: [RehostUploadRemoval(id: id, removedAt: now)])
            return true
        })
    }

    /// Merges another copy's uploads and removals (the iCloud one, #966) and returns the document as saved; see
    /// `RehostUploadHistoryDocument.merging(images:removals:)`. Nothing is saved when nothing changes.
    @discardableResult
    public func merge(
        images: [RehostedImage], removals: [RehostUploadRemoval]
    ) throws(SmallStoreError) -> RehostUploadHistoryDocument {
        _ = try saved(state.mutate { document in
            let merged = document.merging(images: images, removals: removals)
            guard merged != document else { return false }
            document = merged
            return true
        })
        return state.document() ?? .empty
    }

    /// Replaces the whole history (an Apple ID's history set aside or brought back, ADR 0013 Amendment 4). Returns
    /// false when it already held exactly that.
    @discardableResult
    public func replace(with document: RehostUploadHistoryDocument) throws(SmallStoreError) -> Bool {
        try saved(state.mutate { current in
            guard current.images != document.images || current.removals != document.removals else { return false }
            current.images = document.images
            current.removals = document.removals
            return true
        })
    }

    /// Reads the stored data again, for example after the user restored a file. Returns the failure if any.
    @discardableResult
    public func reload() -> SmallStoreError? {
        state.reload()
    }

    /// Sets the unreadable data aside (a `.corrupt` copy for files, never a deletion) and starts from an empty
    /// history. Only call it after the user agreed: this is the single way out of a failed load.
    public func discardUnreadableData() throws(SmallStoreError) {
        try state.discardUnreadableData()
        feed.signal()
    }

    private func saved(_ changed: Bool) -> Bool {
        if changed { feed.signal() }
        return changed
    }
}
