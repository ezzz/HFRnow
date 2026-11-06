import Foundation

/// The smileys each HFR account added to the app's own favourites, on this device (LOT-064).
///
/// Legacy kept one global dictionary keyed by code in `Documents/smiley_favorites_cache2` (`SmileyCache.m:350-439`):
/// adding a code already there changed nothing, and the list showed oldest first. This store keeps those rules, one
/// list per account key (ADR 0013 §7), as versioned JSON. It is the local copy that LOT-172 mirrors to iCloud; reading
/// the legacy archive is LOT-067's importer.
public actor AppSmileyFavoritesStore {
    private var state: SmallStoreState<AppSmileyFavoritesDocument>
    private var feed = ChangeFeed()

    /// Creates a store over `persistence`; nothing is read until the first call.
    public init(persistence: any SmallStorePersistence<AppSmileyFavoritesDocument>) {
        state = SmallStoreState(persistence: persistence)
    }

    // MARK: Reading

    /// The account's favourites, oldest first; empty while the stored data is unreadable.
    public func favorites(for account: String) -> [AppSmileyFavorite] {
        Self.normalized(state.document()?.accounts[AccountKey.make(account)] ?? [])
    }

    /// Whether the smiley `code` is one of the account's favourites (exact comparison).
    public func contains(code: String, account: String) -> Bool {
        favorites(for: account).contains { $0.code == code }
    }

    /// The account keys that hold favourites (ADR 0013 §7); empty while the stored data is unreadable.
    public func accountKeys() -> [String] {
        (state.document()?.accounts.keys).map { $0.sorted() } ?? []
    }

    /// The reason writes are refused, or nil when the store is usable (loading it if needed).
    public func loadFailure() -> SmallStoreError? {
        state.failure()
    }

    /// A signal after each saved change, for the iCloud copy (LOT-172) and the screens showing the lists.
    public func changes() -> AsyncStream<Void> {
        feed.stream()
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
        return try saved(state.mutate { document in
            var list = Self.normalized(document.accounts[key] ?? [])
            guard !list.contains(where: { $0.code == code }) else { return false }
            // After every favourite of the same date or older: oldest first even if the clock moved back.
            let position = list.firstIndex { $0.addedAt > date } ?? list.endIndex
            list.insert(AppSmileyFavorite(code: code, url: url, addedAt: date), at: position)
            document.accounts[key] = list
            return true
        })
    }

    /// Removes the smiley `code` from the account's favourites. Returns false when it was not there.
    @discardableResult
    public func remove(code: String, account: String) throws(SmallStoreError) -> Bool {
        let key = try AccountKey.forWriting(account)
        return try saved(state.mutate { document in
            let list = Self.normalized(document.accounts[key] ?? [])
            guard list.contains(where: { $0.code == code }) else { return false }
            let kept = list.filter { $0.code != code }
            document.accounts[key] = kept.isEmpty ? nil : kept
            return true
        })
    }

    /// Replaces the account's favourites with `favorites` (another device's list, through iCloud, LOT-172), normalised
    /// as a loaded list is; a blank code is dropped. Returns false when the list already was that.
    @discardableResult
    public func replace(_ favorites: [AppSmileyFavorite], account: String) throws(SmallStoreError) -> Bool {
        let key = try AccountKey.forWriting(account)
        let list = Self.normalized(favorites.filter { !$0.code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        return try saved(state.mutate { document in
            guard list != Self.normalized(document.accounts[key] ?? []) else { return false }
            document.accounts[key] = list.isEmpty ? nil : list
            return true
        })
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
        feed.signal()
    }

    // MARK: Internals

    private func saved(_ changed: Bool) -> Bool {
        if changed { feed.signal() }
        return changed
    }

    /// A list as legacy loaded one: each code once (legacy keyed its dictionary by code; the first entry is kept), oldest
    /// first (`SmileyCache.m:371-379`), equal dates in stored order. Lists this store writes are in that form already;
    /// one written by another build or by LOT-067 / LOT-172 may not be.
    private static func normalized(_ list: [AppSmileyFavorite]) -> [AppSmileyFavorite] {
        var seen = Set<String>()
        return list.filter { seen.insert($0.code).inserted }
            .enumerated()
            .sorted { ($0.element.addedAt, $0.offset) < ($1.element.addedAt, $1.offset) }
            .map(\.element)
    }
}
