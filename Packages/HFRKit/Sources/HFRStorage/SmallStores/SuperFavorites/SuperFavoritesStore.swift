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
        state.document()?.accounts[AccountKey.make(account)] ?? []
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
            var list = document.accounts[key] ?? []
            guard !list.contains(where: { $0.topic == topic }) else { return false }
            list.append(SuperFavorite(topic: topic, addedAt: date))
            document.accounts[key] = list.sorted { Self.precedes($0.topic, $1.topic) }
            return true
        }
    }

    /// Unmarks `topic`. Returns false when it was not a super-favourite of the account.
    @discardableResult
    public func remove(_ topic: TopicID, account: String) throws(SmallStoreError) -> Bool {
        let key = try AccountKey.forWriting(account)
        return try state.mutate { document in
            guard var list = document.accounts[key], let index = list.firstIndex(where: { $0.topic == topic }) else {
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

    // MARK: Internals

    /// The saved order: forum categories by number, private messages last, then topic number.
    static func precedes(_ lhs: TopicID, _ rhs: TopicID) -> Bool {
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
