import HFRModels

/// Where each account stopped reading each topic, on this device (LOT-090).
///
/// Legacy kept the visible message anchor only while the topic screen was open (`MessagesView.swift:796-801`), so a
/// relaunch or another window lost it. HFR's own flags stay the position shared with other clients; this store keeps
/// the finer one (page, message, offset). Positions only move forward through `advance`, `reset` sets one explicitly,
/// and each account keeps at most `limitPerAccount` topics: recording a new one evicts the least recently updated.
///
/// Like `PseudoListStore`, a failed load never turns into an empty store that a save would write over: reads answer
/// nothing and writes throw until `reload()` succeeds or `discardUnreadableData()` is called.
public actor ReadingPositionStore {
    private enum State {
        case unloaded
        case loaded(ReadingPositionDocument)
        case failed(ReadingPositionError)
    }

    /// The default number of topics kept per account.
    public static let defaultLimitPerAccount = 500

    /// The number of topics kept per account (at least 1).
    public let limitPerAccount: Int
    private let persistence: any ReadingPositionPersistence
    private var state = State.unloaded

    /// Creates a store over `persistence`; nothing is read until the first call.
    public init(persistence: any ReadingPositionPersistence, limitPerAccount: Int = ReadingPositionStore.defaultLimitPerAccount) {
        self.persistence = persistence
        self.limitPerAccount = max(limitPerAccount, 1)
    }

    // MARK: Reading

    /// The account's position in `topic`; nil when none is stored or the stored data is unreadable.
    public func position(of topic: TopicID, account: String) -> ReadingPosition? {
        document?.accounts[account]?.first { $0.topic == topic }?.position
    }

    /// The account's positions, most recently updated first; empty while the stored data is unreadable.
    public func records(for account: String) -> [ReadingPositionRecord] {
        Self.newestFirst(document?.accounts[account] ?? [])
    }

    /// The reason writes are refused, or nil when the store is usable (loading it if needed).
    public func loadFailure() -> ReadingPositionError? {
        if case .failed(let error) = loadedState() { return error }
        return nil
    }

    // MARK: Writing

    /// Records `position` when it is past the stored one (`ReadingPosition.isAhead(of:)`) or none is stored.
    /// Returns false, and changes nothing, otherwise.
    @discardableResult
    public func advance(_ topic: TopicID, to position: ReadingPosition, account: String) throws -> Bool {
        try write(topic, position, account: account) { stored in stored.map { position.isAhead(of: $0) } ?? true }
    }

    /// Records `position` whatever the stored one, for example when the user goes back to an earlier page on purpose.
    /// Returns false when it equals the stored position.
    @discardableResult
    public func reset(_ topic: TopicID, to position: ReadingPosition, account: String) throws -> Bool {
        try write(topic, position, account: account) { stored in stored != position }
    }

    /// Forgets the account's position in `topic`. Returns false when none was stored.
    @discardableResult
    public func remove(_ topic: TopicID, account: String) throws -> Bool {
        try mutate { document in
            guard var list = document.accounts[account], let index = list.firstIndex(where: { $0.topic == topic }) else {
                return false
            }
            list.remove(at: index)
            document.accounts[account] = list.isEmpty ? nil : list
            return true
        }
    }

    /// Forgets every position of `account`, for example when the account is removed from the app.
    /// Returns false when it had none.
    @discardableResult
    public func removeAccount(_ account: String) throws -> Bool {
        try mutate { document in document.accounts.removeValue(forKey: account) != nil }
    }

    // MARK: Recovery

    /// Reads the stored data again, for example after the user restored a file. Returns the failure if any.
    @discardableResult
    public func reload() -> ReadingPositionError? {
        state = .unloaded
        return loadFailure()
    }

    /// Sets the unreadable data aside (a `.corrupt` copy for files, never a deletion) and starts empty.
    /// Only call it after the user agreed: this is the single way out of a failed load.
    public func discardUnreadableData() throws {
        guard case .failed = loadedState() else { return }
        do {
            try persistence.quarantineUnreadableData()
        } catch {
            throw ReadingPositionError.saveFailed(reason: String(describing: error))
        }
        state = .loaded(ReadingPositionDocument())
    }

    // MARK: Internals

    private var document: ReadingPositionDocument? {
        if case .loaded(let document) = loadedState() { return document }
        return nil
    }

    private func loadedState() -> State {
        if case .unloaded = state {
            do {
                let stored = try persistence.load() ?? ReadingPositionDocument()
                if stored.version > ReadingPositionDocument.currentVersion {
                    state = .failed(.unsupportedVersion(stored.version))
                } else {
                    state = .loaded(stored)
                }
            } catch {
                state = .failed(.loadFailed(reason: String(describing: error)))
            }
        }
        return state
    }

    /// Validates, then stores `position` for `topic` when `accepts` says so, evicting beyond the limit.
    private func write(
        _ topic: TopicID, _ position: ReadingPosition, account: String, accepts: (ReadingPosition?) -> Bool
    ) throws -> Bool {
        guard !account.isEmpty else { throw ReadingPositionError.emptyAccount }
        guard topic.topic > 0, position.isValid else { throw ReadingPositionError.invalidPosition }
        let limit = limitPerAccount
        return try mutate { document in
            var list = document.accounts[account] ?? []
            let index = list.firstIndex { $0.topic == topic }
            guard accepts(index.map { list[$0].position }) else { return false }
            if let index {
                list[index].position = position
            } else {
                list.append(ReadingPositionRecord(topic: topic, position: position))
            }
            if list.count > limit {
                // The record just written is kept even when its date is older than the others' (a clock change).
                let kept = Self.newestFirst(list.filter { $0.topic != topic }).prefix(limit - 1)
                list = Array(kept) + [ReadingPositionRecord(topic: topic, position: position)]
            }
            document.accounts[account] = list
            return true
        }
    }

    /// Applies `change` to a copy, persists it, then publishes it: memory never gets ahead of the disk.
    private func mutate(_ change: (inout ReadingPositionDocument) throws -> Bool) throws -> Bool {
        switch loadedState() {
        case .failed(let error):
            throw error
        case .unloaded:
            throw ReadingPositionError.loadFailed(reason: "unreachable state")
        case .loaded(let current):
            var updated = current
            guard try change(&updated) else { return false }
            do {
                try persistence.save(updated)
            } catch {
                throw ReadingPositionError.saveFailed(reason: String(describing: error))
            }
            state = .loaded(updated)
            return true
        }
    }

    /// Most recently updated first; ties broken by topic so the order never depends on storage order.
    private static func newestFirst(_ records: [ReadingPositionRecord]) -> [ReadingPositionRecord] {
        records.sorted { lhs, rhs in
            if lhs.position.updatedAt != rhs.position.updatedAt { return lhs.position.updatedAt > rhs.position.updatedAt }
            if lhs.topic.category.queryValue != rhs.topic.category.queryValue {
                return lhs.topic.category.queryValue < rhs.topic.category.queryValue
            }
            return lhs.topic.topic < rhs.topic.topic
        }
    }
}
