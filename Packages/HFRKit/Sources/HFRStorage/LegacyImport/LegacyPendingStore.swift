import Foundation
import HFRModels

/// A legacy super-favourite waiting for its category: legacy kept the topic number alone (`Favorites.swift:132-157`).
public struct PendingSuperFavorite: Sendable, Hashable, Codable {
    /// The topic number.
    public var number: Int
    /// When the import set it aside; it expires `LegacyPendingStore.superFavoriteLifetime` later.
    public var importedAt: Date

    /// Creates a pending super-favourite.
    public init(number: Int, importedAt: Date) {
        self.number = number
        self.importedAt = importedAt
    }
}

/// A legacy reply draft waiting for its topic: legacy kept it under `post-<topic number>` (`MessagesView.swift:3254-3262`).
public struct PendingReplyDraft: Sendable, Hashable, Codable {
    /// The topic number.
    public var number: Int
    /// The draft text.
    public var text: String
    /// When legacy last saved it; it expires `DraftStore.defaultTimeToLive` later, like a LOT-063 draft.
    public var updatedAt: Date

    /// Creates a pending draft.
    public init(number: Int, text: String, updatedAt: Date) {
        self.number = number
        self.text = text
        self.updatedAt = updatedAt
    }
}

/// The pending lists of the legacy import, per account key (`AccountKey`). Device-only, removed with the import code later.
public struct LegacyPendingDocument: SmallStoreDocument {
    /// The format of this document.
    public static let currentVersion = 1
    /// Nothing pending.
    public static var empty: Self { Self() }

    /// Format version of this document.
    public var version: Int
    /// Super-favourites waiting for the favourites list, per account key.
    public var superFavorites: [String: [PendingSuperFavorite]]
    /// Reply drafts waiting for their topic, per account key.
    public var replyDrafts: [String: [PendingReplyDraft]]

    /// Creates a document.
    public init(
        version: Int = Self.currentVersion,
        superFavorites: [String: [PendingSuperFavorite]] = [:],
        replyDrafts: [String: [PendingReplyDraft]] = [:]
    ) {
        self.version = version
        self.superFavorites = superFavorites
        self.replyDrafts = replyDrafts
    }
}

/// Legacy items the import could not place because legacy did not store enough (operator decisions D1 and D2, LOT-067):
/// super-favourites without a category and reply drafts without a topic. One resolver for both: the app calls
/// `resolveSuperFavorites` at each favourites-list load and `resolveReplyDraft` when it opens a topic; each places what
/// matches into the ordinary store and forgets it. Expired entries are dropped by every call.
public actor LegacyPendingStore {
    /// How long a pending super-favourite waits for the favourites list (90 days).
    public static let superFavoriteLifetime: TimeInterval = 90 * 24 * 60 * 60
    /// How long a pending reply draft waits for its topic: LOT-063's draft lifetime (30 days).
    public static let replyDraftLifetime: TimeInterval = DraftStore.defaultTimeToLive

    private var state: SmallStoreState<LegacyPendingDocument>

    /// Creates a store over `persistence`; nothing is read until the first call.
    public init(persistence: any SmallStorePersistence<LegacyPendingDocument>) {
        state = SmallStoreState(persistence: persistence)
    }

    // MARK: Reading

    /// The topic numbers still waiting for a category, sorted.
    public func pendingSuperFavorites(for account: String) -> [Int] {
        (state.document()?.superFavorites[AccountKey.make(account)] ?? []).map(\.number).sorted()
    }

    /// The reply drafts still waiting for their topic.
    public func pendingReplyDrafts(for account: String) -> [PendingReplyDraft] {
        state.document()?.replyDrafts[AccountKey.make(account)] ?? []
    }

    /// The account keys with anything pending (LOT-157 lists them as data left on the device); none when unreadable.
    public func accountKeys() -> Set<String> {
        guard let document = state.document() else { return [] }
        return Set(document.superFavorites.keys).union(document.replyDrafts.keys)
    }

    /// The reason writes are refused, or nil when the store is usable (loading it if needed).
    public func loadFailure() -> SmallStoreError? {
        state.failure()
    }

    // MARK: Import side

    /// Sets topic numbers aside for `account` (numbers ≤ 0 and numbers already pending are skipped). Returns how many
    /// were added.
    @discardableResult
    public func addSuperFavorites(_ numbers: [Int], account: String, at date: Date) throws(SmallStoreError) -> Int {
        let key = try Self.key(account)
        var added = 0
        _ = try state.mutate { document in
            var list = document.superFavorites[key] ?? []
            added = 0
            for number in numbers where number > 0 && !list.contains(where: { $0.number == number }) {
                list.append(PendingSuperFavorite(number: number, importedAt: date))
                added += 1
            }
            guard added > 0 else { return false }
            document.superFavorites[key] = list
            return true
        }
        return added
    }

    /// Sets reply drafts aside for `account`: one per topic number (the first given wins), blank texts and drafts
    /// already expired at `date` skipped, a number already pending kept as it is. Returns how many were added.
    @discardableResult
    public func addReplyDrafts(_ drafts: [PendingReplyDraft], account: String, at date: Date) throws(SmallStoreError) -> Int {
        let key = try Self.key(account)
        var added = 0
        _ = try state.mutate { document in
            var list = document.replyDrafts[key] ?? []
            added = 0
            for draft in drafts where draft.number > 0 && !Self.isExpired(draft, at: date)
                && !draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !list.contains(where: { $0.number == draft.number }) {
                list.append(draft)
                added += 1
            }
            guard added > 0 else { return false }
            document.replyDrafts[key] = list
            return true
        }
        return added
    }

    // MARK: Resolver

    /// Places the pending super-favourites of `account` found in `listed` (the favourites list just loaded): each
    /// number becomes a super-favourite in every category where the list shows it (legacy matched the number alone),
    /// then leaves the pending list. Numbers not listed stay pending until they expire. Returns how many topics were
    /// added. When `superFavorites` fails, nothing pending is forgotten.
    @discardableResult
    public func resolveSuperFavorites(
        listed: [TopicID],
        account: String,
        into superFavorites: SuperFavoritesStore,
        now: Date = .now
    ) async throws(SmallStoreError) -> Int {
        let key = try Self.key(account)
        try dropExpired(now: now)
        let pending = state.document()?.superFavorites[key] ?? []
        let numbers = Set(pending.map(\.number))
        let matches = Set(listed.filter { numbers.contains($0.topic) })
        guard !matches.isEmpty else { return 0 }
        var added = 0
        for topic in matches.sorted(by: { ($0.category.queryValue, $0.topic) < ($1.category.queryValue, $1.topic) })
        where try await superFavorites.add(topic, account: account, at: now) {
            added += 1
        }
        let resolved = Set(matches.map(\.topic))
        _ = try state.mutate { document in
            document.superFavorites[key]?.removeAll { resolved.contains($0.number) }
            if document.superFavorites[key]?.isEmpty == true { document.superFavorites[key] = nil }
            return true
        }
        return added
    }

    /// Forgets every pending super-favourite of `account`: the user emptied the super-favourites (decision D2).
    public func discardPendingSuperFavorites(account: String) throws(SmallStoreError) {
        let key = try Self.key(account)
        _ = try state.mutate { document in
            document.superFavorites.removeValue(forKey: key) != nil
        }
    }

    /// Forgets everything pending for `account` (LOT-157, the account's data erased from this device).
    public func discardAll(account: String) throws(SmallStoreError) {
        let key = try Self.key(account)
        _ = try state.mutate { document in
            let hadFavorites = document.superFavorites.removeValue(forKey: key) != nil
            let hadDrafts = document.replyDrafts.removeValue(forKey: key) != nil
            return hadFavorites || hadDrafts
        }
    }

    /// When a topic opens: turns the pending draft of its number into the ordinary reply draft of `context`, unless
    /// that context already has one (the newer SwiftHFR draft wins), then forgets it. Only `.reply` contexts match.
    /// Returns true when a draft was written. When `drafts` fails, the pending draft is kept.
    @discardableResult
    public func resolveReplyDraft(
        for context: DraftContext,
        account: String,
        into drafts: DraftStore,
        now: Date = .now
    ) async throws -> Bool {
        guard case .reply(let topic, _) = context else { return false }
        let key = try Self.key(account)
        try dropExpired(now: now)
        guard let pending = state.document()?.replyDrafts[key]?.first(where: { $0.number == topic.topic }) else {
            return false
        }
        var written = false
        if await drafts.draft(for: context, account: account) == nil {
            try await drafts.save(pending.text, for: context, account: account)
            written = true
        }
        _ = try state.mutate { document in
            document.replyDrafts[key]?.removeAll { $0.number == pending.number }
            if document.replyDrafts[key]?.isEmpty == true { document.replyDrafts[key] = nil }
            return true
        }
        return written
    }

    // MARK: Internals

    private static func key(_ account: String) throws(SmallStoreError) -> String {
        let key = AccountKey.make(account)
        guard !key.isEmpty else { throw .emptyAccount }
        return key
    }

    private static func isExpired(_ draft: PendingReplyDraft, at date: Date) -> Bool {
        draft.updatedAt.addingTimeInterval(replyDraftLifetime) < date
    }

    private func dropExpired(now: Date) throws(SmallStoreError) {
        _ = try state.mutate { document in
            let before = document
            for (key, list) in document.superFavorites {
                let kept = list.filter { $0.importedAt.addingTimeInterval(Self.superFavoriteLifetime) >= now }
                document.superFavorites[key] = kept.isEmpty ? nil : kept
            }
            for (key, list) in document.replyDrafts {
                let kept = list.filter { !Self.isExpired($0, at: now) }
                document.replyDrafts[key] = kept.isEmpty ? nil : kept
            }
            return document != before
        }
    }
}
