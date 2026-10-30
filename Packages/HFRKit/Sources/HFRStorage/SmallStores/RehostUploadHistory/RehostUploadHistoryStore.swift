import HFRModels

/// The images uploaded to the image host from this device, to insert them again later (LOT-064).
///
/// Legacy kept them in `Documents/rehostImagesSwiftUI.json` (`ReplyService.swift:1895-1920`): each upload inserted at
/// the top (`AnswerView.swift:656`), a swipe removed one by identity (`AnswerView.swift:1909`), no limit. This store
/// keeps those rules with `RehostedImage.id` as the identity, and adds nothing twice.
public actor RehostUploadHistoryStore {
    private var state: SmallStoreState<RehostUploadHistoryDocument>

    /// Creates a store over `persistence`; nothing is read until the first call.
    public init(persistence: any SmallStorePersistence<RehostUploadHistoryDocument>) {
        state = SmallStoreState(persistence: persistence)
    }

    /// The uploaded images, the last one added first; empty while the stored data is unreadable.
    public func images() -> [RehostedImage] {
        state.document()?.images ?? []
    }

    /// The reason writes are refused, or nil when the store is usable (loading it if needed).
    public func loadFailure() -> SmallStoreError? {
        state.failure()
    }

    /// Adds an uploaded image at the top. Returns false when an image with the same `id` is already there.
    @discardableResult
    public func add(_ image: RehostedImage) throws(SmallStoreError) -> Bool {
        try state.mutate { document in
            guard !document.images.contains(where: { $0.id == image.id }) else { return false }
            document.images.insert(image, at: 0)
            return true
        }
    }

    /// Removes the image whose `RehostedImage.id` is `id`. Returns false when it was not there.
    @discardableResult
    public func remove(id: String) throws(SmallStoreError) -> Bool {
        try state.mutate { document in
            guard let index = document.images.firstIndex(where: { $0.id == id }) else { return false }
            document.images.remove(at: index)
            return true
        }
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
    }
}
