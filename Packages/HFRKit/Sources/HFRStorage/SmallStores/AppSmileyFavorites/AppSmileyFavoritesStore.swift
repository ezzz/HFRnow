import Foundation

/// The smileys each HFR account added to the app's own favourites, on this device (LOT-064).
///
/// Legacy kept one global dictionary keyed by code in `Documents/smiley_favorites_cache2` (`SmileyCache.m:350-439`):
/// adding a code already there changed nothing, and the list showed oldest first. This store keeps those rules, one
/// list per account key (ADR 0013 §7), as versioned JSON. It is the local copy that LOT-172 mirrors to iCloud; reading
/// the legacy archive is LOT-067's importer.
public actor AppSmileyFavoritesStore {
    private var state: SmallStoreState<AppSmileyFavoritesDocument>

    /// Creates a store over `persistence`; nothing is read until the first call.
    public init(persistence: any SmallStorePersistence<AppSmileyFavoritesDocument>) {
        state = SmallStoreState(persistence: persistence)
    }

    // MARK: Reading

    /// The account's favourites, oldest first; empty while the stored data is unreadable.
    public func favorites(for account: String) -> [AppSmileyFavorite] {
        state.document()?.accounts[AccountKey.make(account)] ?? []
    }

    /// Whether the smiley `code` is one of the account's favourites (exact comparison).
    public func contains(code: String, account: String) -> Bool {
        favorites(for: account).contains { $0.code == code }
    }

    /// The reason writes are refused, or nil when the store is usable (loading it if needed).
    public func loadFailure() -> SmallStoreError? {
        state.failure()
    }

    // MARK: Writing

    /// Adds a smiley to the account's favourites, in date order. Returns false when its code already was there
    /// (the stored URL and date are kept, as legacy's `AddAndSaveDicFavoritesApp` returned `NO`).
    @discardableResult
    public func add(code: String, url: URL, account: String, at date: Date = .now) throws(SmallStoreError) -> Bool {
        guard !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw .invalidValue(reason: "empty smiley code")
        }
        let key = try AccountKey.forWriting(account)
        return try state.mutate { document in
            var list = document.accounts[key] ?? []
            guard !list.contains(where: { $0.code == code }) else { return false }
            // After every favourite of the same date or older: oldest first even if the clock moved back.
            let position = list.firstIndex { $0.addedAt > date } ?? list.endIndex
            list.insert(AppSmileyFavorite(code: code, url: url, addedAt: date), at: position)
            document.accounts[key] = list
            return true
        }
    }

    /// Removes the smiley `code` from the account's favourites. Returns false when it was not there.
    @discardableResult
    public func remove(code: String, account: String) throws(SmallStoreError) -> Bool {
        let key = try AccountKey.forWriting(account)
        return try state.mutate { document in
            guard var list = document.accounts[key], let index = list.firstIndex(where: { $0.code == code }) else {
                return false
            }
            list.remove(at: index)
            document.accounts[key] = list.isEmpty ? nil : list
            return true
        }
    }

    // MARK: Recovery

    /// Reads the stored data again, for example after the user restored a file. Returns the failure if any.
    @discardableResult
    public func reload() -> SmallStoreError? {
        state.reload()
    }

    /// Sets the unreadable data aside (a `.corrupt` copy for files, never a deletion) and starts from empty lists.
    /// Only call it after the user agreed: this is the single way out of a failed load.
    public func discardUnreadableData() throws(SmallStoreError) {
        try state.discardUnreadableData()
    }
}
