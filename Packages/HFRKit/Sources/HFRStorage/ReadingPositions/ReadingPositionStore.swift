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
    private var feed = ChangeFeed()

    /// Creates a store over `persistence`; nothing is read until the first call.
    public init(persistence: any ReadingPositionPersistence, limitPerAccount: Int = ReadingPositionStore.defaultLimitPerAccount) {
        self.persistence = persistence
        self.limitPerAccount = max(limitPerAccount, 1)
    }

    // MARK: Reading

    /// The account's position in `topic`; nil when none is stored or the stored data is unreadable.
    public func position(of topic: TopicID, account: String) -> ReadingPosition? {
        document?.accounts[AccountKey.make(account)]?.first { $0.topic == topic }?.position
    }

    /// The account's positions, most recently updated first; empty while the stored data is unreadable.
    public func records(for account: String) -> [ReadingPositionRecord] {
        Self.newestFirst(document?.accounts[AccountKey.make(account)] ?? [])
    }

    /// The account keys (`AccountKey`) holding positions; empty while the stored data is unreadable.
    public func accounts() -> [String] {
        (document?.accounts.keys).map { $0.sorted() } ?? []
    }

    /// The reason writes are refused, or nil when the store is usable (loading it if needed).
    public func loadFailure() -> ReadingPositionError? {
        if case .failed(let error) = loadedState() { return error }
        return nil
    }

    /// A signal after each saved change, for the iCloud copy (LOT-172).
    public func changes() -> AsyncStream<Void> {
        feed.stream()
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
        let key = AccountKey.make(account)
        return try mutate { document in
            guard var list = document.accounts[key], let index = list.firstIndex(where: { $0.topic == topic }) else {
                return false
            }
            list.remove(at: index)
            document.accounts[key] = list.isEmpty ? nil : list
            return true
        }
    }

    /// Merges `records` (another device's, through iCloud, LOT-172) into the account's positions: per topic the newest
    /// `updatedAt` wins whatever the page (a move back elsewhere is newer), equal dates go to the position ahead, so
    /// every device ends with the same records. Invalid records are skipped; beyond the limit the newest are kept.
    /// Returns false when nothing changed.
    @discardableResult
    public func merge(_ records: [ReadingPositionRecord], account: String) throws -> Bool {
        let key = AccountKey.make(account)
        guard !key.isEmpty else { throw ReadingPositionError.emptyAccount }
        let limit = limitPerAccount
        return try mutate { document in
            let stored = document.accounts[key] ?? []
            var byTopic = Dictionary(stored.map { ($0.topic, $0.position) }, uniquingKeysWith: { first, _ in first })
            for record in records where record.topic.topic > 0 && record.position.isValid {
                guard let current = byTopic[record.topic] else {
                    byTopic[record.topic] = record.position
                    continue
                }
                if Self.wins(record.position, over: current) { byTopic[record.topic] = record.position }
            }
            let merged = Array(Self.newestFirst(byTopic.map { ReadingPositionRecord(topic: $0.key, position: $0.value) }).prefix(limit))
            guard Set(merged) != Set(stored) else { return false }
            document.accounts[key] = merged.isEmpty ? nil : merged
            return true
        }
    }

    /// Forgets every position of `account`, for example when the account is removed from the app.
    /// Returns false when it had none.
    @discardableResult
    public func removeAccount(_ account: String) throws -> Bool {
        let key = AccountKey.make(account)
        return try mutate { document in document.accounts.removeValue(forKey: key) != nil }
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
        // Read again first: a read that failed once (an I/O error) and works now is not set aside (#1182).
        state = .unloaded
        guard case .failed = loadedState() else { return }
        do {
            try persistence.quarantineUnreadableData()
        } catch {
            throw ReadingPositionError.saveFailed(reason: String(describing: error))
        }
        state = .loaded(ReadingPositionDocument())
        feed.signal()
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
                } else if stored.version < 1 {
                    state = .failed(.loadFailed(reason: "invalid version \(stored.version)"))
                } else {
                    state = .loaded(Self.keyedByAccount(stored))
                }
            } catch let error as ReadingPositionError {
                state = .failed(error)
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
        let key = AccountKey.make(account)
        guard !key.isEmpty else { throw ReadingPositionError.emptyAccount }
        guard topic.topic > 0, position.isValid else { throw ReadingPositionError.invalidPosition }
        let limit = limitPerAccount
        return try mutate { document in
            var list = document.accounts[key] ?? []
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
            document.accounts[key] = list
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
            feed.signal()
            return true
        }
    }

    /// The document with its accounts under their key (#1184). Files written before stored positions under the spelling the
    /// reader used: the spellings of one key are merged, per topic the position that `wins`, nothing dropped (the limit is
    /// applied by the next `advance`, `reset` or `merge` of that account). A document already keyed is returned as it is.
    static func keyedByAccount(_ document: ReadingPositionDocument) -> ReadingPositionDocument {
        guard document.accounts.keys.contains(where: { AccountKey.make($0) != $0 }) else { return document }
        var keyed = document
        keyed.accounts = [:]
        for name in document.accounts.keys.sorted() {
            let key = AccountKey.make(name)
            var byTopic: [TopicID: ReadingPosition] = [:]
            for record in (keyed.accounts[key] ?? []) + (document.accounts[name] ?? []) {
                if let current = byTopic[record.topic], !Self.wins(record.position, over: current) { continue }
                byTopic[record.topic] = record.position
            }
            keyed.accounts[key] = Self.newestFirst(byTopic.map { ReadingPositionRecord(topic: $0.key, position: $0.value) })
        }
        return keyed
    }

    /// Whether `incoming` replaces `current` for one topic: the newest `updatedAt`, equal dates to the position ahead.
    private static func wins(_ incoming: ReadingPosition, over current: ReadingPosition) -> Bool {
        incoming.updatedAt > current.updatedAt || (incoming.updatedAt == current.updatedAt && incoming.isAhead(of: current))
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
