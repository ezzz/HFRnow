import Foundation
import HFRModels

/// The topics each HFR account marked as super-favourites, on this device (LOT-064).
///
/// Legacy kept one global list of topic numbers in `UserDefaults` (`SuperFavoritesIds`, `Favorites.swift:112-136`):
/// numbers above 0, no duplicates, saved sorted. This store keeps those rules, one list per account key (ADR 0013 §7),
/// and identifies a topic by category and number. It is the local copy that LOT-172 mirrors to iCloud.
public actor SuperFavoritesStore {
    private var state: SmallStoreState<SuperFavoritesDocument>

    /// Creates a store over `persistence`; nothing is read until the first call.
    public init(persistence: any SmallStorePersistence<SuperFavoritesDocument>) {
        state = SmallStoreState(persistence: persistence)
    }

    // MARK: Reading

    /// The account's super-favourites, by category then topic number; empty while the stored data is unreadable.
    public func favorites(for account: String) -> [SuperFavorite] {
        Self.normalized(state.document()?.accounts[AccountKey.make(account)] ?? [])
    }

    /// Whether `topic` is one of the account's super-favourites.
    public func contains(_ topic: TopicID, account: String) -> Bool {
        favorites(for: account).contains { $0.topic == topic }
    }

    /// The reason writes are refused, or nil when the store is usable (loading it if needed).
    public func loadFailure() -> SmallStoreError? {
        state.failure()
    }

    // MARK: Writing

    /// Marks `topic` as a super-favourite of the account. Returns false when it already was (its date is kept).
    @discardableResult
    public func add(_ topic: TopicID, account: String, at date: Date = .now) throws(SmallStoreError) -> Bool {
        guard topic.topic > 0 else { throw .invalidValue(reason: "topic number \(topic.topic)") }
        let key = try AccountKey.forWriting(account)
        return try state.mutate { document in
            let list = Self.normalized(document.accounts[key] ?? [])
            guard !list.contains(where: { $0.topic == topic }) else { return false }
            document.accounts[key] = Self.normalized(list + [SuperFavorite(topic: topic, addedAt: date)])
            return true
        }
    }

    /// Unmarks `topic`. Returns false when it was not a super-favourite of the account.
    @discardableResult
    public func remove(_ topic: TopicID, account: String) throws(SmallStoreError) -> Bool {
        let key = try AccountKey.forWriting(account)
        return try state.mutate { document in
            let list = Self.normalized(document.accounts[key] ?? [])
            guard list.contains(where: { $0.topic == topic }) else { return false }
            let kept = list.filter { $0.topic != topic }
            document.accounts[key] = kept.isEmpty ? nil : kept
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

    // MARK: Internals

    /// A list as legacy loaded one (`Favorites.swift:115-131`): topic numbers above 0, each topic once (its first entry
    /// kept), by category then topic number. Lists this store writes are in that form already; one written by another
    /// build or by LOT-067 / LOT-172 may not be.
    private static func normalized(_ list: [SuperFavorite]) -> [SuperFavorite] {
        var seen = Set<TopicID>()
        return list.filter { $0.topic.topic > 0 && seen.insert($0.topic).inserted }.sorted { precedes($0.topic, $1.topic) }
    }

    /// The saved order: forum categories by number, private messages last, then topic number.
    private static func precedes(_ lhs: TopicID, _ rhs: TopicID) -> Bool {
        let left = rank(of: lhs.category)
        let right = rank(of: rhs.category)
        return left == right ? lhs.topic < rhs.topic : left < right
    }

    private static func rank(of category: CategoryID) -> (Int, Int) {
        switch category {
        case .forum(let number): (0, number)
        case .privateMessages: (1, 0)
        }
    }
}
