import Foundation

/// Drafts per account and context, with a time-to-live and a size bound.
///
/// Persistence is one atomic JSON document. Every save rewrites it, so callers should debounce keystrokes.
/// A document that cannot be decoded (corrupt, or from a newer version) is moved aside as `.corrupt` and the store starts
/// empty: a draft is not worth blocking the composer. A document that cannot be *read* (I/O error) blocks writes
/// instead, so a transient failure never replaces good data.
public actor DraftStore {
    /// How long a draft lives after its last save: 30 days.
    public static let defaultTimeToLive: TimeInterval = 30 * 24 * 60 * 60
    /// How many drafts are kept: when exceeded, the least recently saved are dropped.
    public static let defaultMaximumCount = 100

    private enum State {
        case unloaded
        case loaded(DraftDocument)
        case failed(DraftError)
    }

    private let persistence: any DraftPersistence
    private let timeToLive: TimeInterval
    private let maximumCount: Int
    private let clock: @Sendable () -> Date
    private var state = State.unloaded
    private var recoveredCorruptData = false

    /// Creates a store; nothing is read until the first call. `clock` is injectable for tests.
    public init(
        persistence: any DraftPersistence,
        timeToLive: TimeInterval = DraftStore.defaultTimeToLive,
        maximumCount: Int = DraftStore.defaultMaximumCount,
        clock: @escaping @Sendable () -> Date = { Date.now }
    ) {
        self.persistence = persistence
        self.timeToLive = timeToLive
        self.maximumCount = max(1, maximumCount)
        self.clock = clock
    }

    // MARK: Reading

    /// The live draft of a context, or nil when none was saved or it expired.
    public func draft(for context: DraftContext, account: String) -> Draft? {
        let now = clock()
        return liveDrafts(now: now).first { Self.matches($0, context, account) }
    }

    /// Every live draft of an account, most recently saved first.
    public func drafts(account: String) -> [Draft] {
        let key = DraftNameNormalizer.normalize(account)
        return liveDrafts(now: clock()).filter { $0.account == key }.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Why writes are refused (an I/O failure while reading), or nil.
    public func loadFailure() -> DraftError? {
        if case .failed(let error) = loadedState() { return error }
        return nil
    }

    /// Whether the last load found undecodable data and moved it aside to `.corrupt`.
    public func didRecoverFromCorruptData() -> Bool {
        _ = loadedState()
        return recoveredCorruptData
    }

    // MARK: Writing

    /// Saves the draft of a context. Empty text and subject remove the draft instead of storing nothing.
    public func save(_ text: String, subject: String? = nil, for context: DraftContext, account: String) throws {
        let now = clock()
        let key = DraftNameNormalizer.normalize(account)
        let hasContent = !text.isEmpty || !(subject ?? "").isEmpty
        try mutate { drafts in
            let original = drafts
            drafts.removeAll { Self.matches($0, context, account) }
            if hasContent {
                drafts.append(Draft(context: context, account: key, text: text, subject: subject, updatedAt: now))
            }
            drafts.removeAll { self.isExpired($0, now: now) }
            if drafts.count > self.maximumCount {
                drafts.sort { $0.updatedAt > $1.updatedAt }
                drafts.removeLast(drafts.count - self.maximumCount)
            }
            return drafts != original
        }
    }

    /// Removes the draft of a context, typically after the message was posted. Returns false when there was none.
    @discardableResult
    public func discard(for context: DraftContext, account: String) throws -> Bool {
        try mutate { drafts in
            let before = drafts.count
            drafts.removeAll { Self.matches($0, context, account) }
            return drafts.count != before
        }
    }

    /// Removes every draft of an account (logout). Returns how many were removed.
    @discardableResult
    public func discardAll(account: String) throws -> Int {
        let key = DraftNameNormalizer.normalize(account)
        var removed = 0
        try mutate { drafts in
            let before = drafts.count
            drafts.removeAll { $0.account == key }
            removed = before - drafts.count
            return removed > 0
        }
        return removed
    }

    /// Deletes the expired drafts from the file; reads already ignore them. Returns how many were removed.
    @discardableResult
    public func purgeExpired() throws -> Int {
        let now = clock()
        var removed = 0
        try mutate { drafts in
            let before = drafts.count
            drafts.removeAll { self.isExpired($0, now: now) }
            removed = before - drafts.count
            return removed > 0
        }
        return removed
    }

    /// Reads the stored data again after an I/O failure. Returns the failure if any.
    @discardableResult
    public func reload() -> DraftError? {
        state = .unloaded
        return loadFailure()
    }

    // MARK: Internals

    private func liveDrafts(now: Date) -> [Draft] {
        guard case .loaded(let document) = loadedState() else { return [] }
        return document.drafts.filter { !isExpired($0, now: now) }
    }

    private func isExpired(_ draft: Draft, now: Date) -> Bool {
        now.timeIntervalSince(draft.updatedAt) > timeToLive
    }

    private static func matches(_ draft: Draft, _ context: DraftContext, _ account: String) -> Bool {
        draft.account == DraftNameNormalizer.normalize(account) && draft.context.storageKey == context.storageKey
    }

    private func loadedState() -> State {
        guard case .unloaded = state else { return state }
        do {
            let stored = try persistence.load() ?? DraftDocument()
            if stored.version > DraftDocument.currentVersion {
                state = quarantine(reason: "newer format version \(stored.version)")
            } else {
                state = .loaded(stored)
            }
        } catch is DecodingError {
            state = quarantine(reason: "undecodable data")
        } catch {
            state = .failed(.loadFailed(reason: String(describing: error)))
        }
        return state
    }

    private func quarantine(reason: String) -> State {
        do {
            try persistence.quarantineUnreadableData()
            recoveredCorruptData = true
            return .loaded(DraftDocument())
        } catch {
            return .failed(.loadFailed(reason: "\(reason); could not set it aside: \(error)"))
        }
    }

    /// Applies `change` to a copy of the drafts, persists it, then publishes it: memory never gets ahead of the disk.
    @discardableResult
    private func mutate(_ change: (inout [Draft]) -> Bool) throws -> Bool {
        guard case .loaded(let current) = loadedState() else {
            throw loadFailure() ?? DraftError.loadFailed(reason: "not loaded")
        }
        var updated = current
        guard change(&updated.drafts) else { return false }
        do {
            try persistence.save(updated)
        } catch {
            throw DraftError.saveFailed(reason: String(describing: error))
        }
        state = .loaded(updated)
        return true
    }
}
