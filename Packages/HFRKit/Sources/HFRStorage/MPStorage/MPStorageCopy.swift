import Foundation

/// What this device keeps of one account's MPStorage document (ADR 0013 §2 and appendix B, LOT-130): device-only, never in
/// iCloud, since the texts hold member pseudos.
public struct MPStorageCopy: Sendable, Hashable, Codable {
    /// The storage thread's id (legacy `dicMPStorage_postid`); nil until found.
    public var post: Int?
    /// The document text last read or written: the base of LOT-062's three-way merge.
    public var base: String?
    /// The document text with the local edits not yet written; nil when there are none.
    public var pending: String?
    /// The last successful read or write ("Dernier accès").
    public var lastSync: Date?
    /// The last search of the MP list that found no thread.
    public var lastSearch: Date?

    /// Creates a copy.
    public init(post: Int? = nil, base: String? = nil, pending: String? = nil, lastSync: Date? = nil, lastSearch: Date? = nil) {
        self.post = post
        self.base = base
        self.pending = pending
        self.lastSync = lastSync
        self.lastSearch = lastSearch
    }
}

/// The device copies of every account, in one file so a save is atomic.
public struct MPStorageCopyDocument: SmallStoreDocument {
    /// Format version written by this code.
    public static let currentVersion = 1
    /// A document without any copy.
    public static var empty: Self { Self() }

    /// Format version.
    public var version: Int
    /// Copies keyed by account key (ADR 0013 §7).
    public var accounts: [String: MPStorageCopy]

    /// Creates a document.
    public init(version: Int = Self.currentVersion, accounts: [String: MPStorageCopy] = [:]) {
        self.version = version
        self.accounts = accounts
    }
}

/// The device copies of the accounts' MPStorage documents (LOT-130), with the small stores' rule: unreadable or newer data
/// is never saved over.
public actor MPStorageCopyStore {
    private var state: SmallStoreState<MPStorageCopyDocument>

    /// Creates a store over `persistence`; nothing is read until the first call.
    public init(persistence: any SmallStorePersistence<MPStorageCopyDocument>) {
        state = SmallStoreState(persistence: persistence)
    }

    /// The account's copy; an empty copy when none is stored, nil while the stored data is unreadable.
    public func copy(for account: String) -> MPStorageCopy? {
        guard let document = state.document() else { return nil }
        return document.accounts[AccountKey.make(account)] ?? MPStorageCopy()
    }

    /// Replaces the account's copy.
    public func save(_ copy: MPStorageCopy, for account: String) throws(SmallStoreError) {
        let key = try AccountKey.forWriting(account)
        _ = try state.mutate { document in
            guard document.accounts[key] != copy else { return false }
            document.accounts[key] = copy
            return true
        }
    }

    /// The reason writes are refused, or nil when the store is usable (loading it if needed).
    public func loadFailure() -> SmallStoreError? {
        state.failure()
    }
}
