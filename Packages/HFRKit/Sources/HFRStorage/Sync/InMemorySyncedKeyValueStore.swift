import Synchronization

/// A key-value store kept in memory, for tests and previews; `receive` plays what the system would report.
public final class InMemorySyncedKeyValueStore: SyncedKeyValueStore {
    private struct State {
        var values: [String: SyncedValue] = [:]
        var identity: String?
        var subscribers: [AsyncStream<SyncedStoreChange>.Continuation] = []
        var synchronizeCount = 0
    }

    private let state: Mutex<State>

    /// Creates a store holding `values` for the iCloud account `identity`.
    public init(_ values: [String: SyncedValue] = [:], identity: String? = "account-1") {
        state = Mutex(State(values: values, identity: identity))
    }

    /// Every stored value.
    public var values: [String: SyncedValue] {
        state.withLock { $0.values }
    }

    /// How many times `synchronize()` was called.
    public var synchronizeCount: Int {
        state.withLock { $0.synchronizeCount }
    }

    public func value(forKey key: String) -> SyncedValue? {
        state.withLock { $0.values[key] }
    }

    public func set(_ value: SyncedValue, forKey key: String) {
        state.withLock { $0.values[key] = value }
    }

    public func removeValue(forKey key: String) {
        state.withLock { $0.values[key] = nil }
    }

    @discardableResult
    public func synchronize() -> Bool {
        state.withLock { $0.synchronizeCount += 1 }
        return true
    }

    public func accountIdentity() -> String? {
        state.withLock { $0.identity }
    }

    public func changes() -> AsyncStream<SyncedStoreChange> {
        let (stream, continuation) = AsyncStream<SyncedStoreChange>.makeStream()
        state.withLock { $0.subscribers.append(continuation) }
        return stream
    }

    /// Plays a change from iCloud: the keys of `updates` take their value (nil removes), then subscribers are told.
    /// With `identity`, the store first switches to that account and keeps only `updates` (an account change).
    public func receive(_ change: SyncedStoreChange, updates: [String: SyncedValue?] = [:], identity: String?? = nil) {
        let subscribers = state.withLock { state -> [AsyncStream<SyncedStoreChange>.Continuation] in
            if let identity {
                state.identity = identity
                state.values = [:]
            }
            for (key, value) in updates { state.values[key] = value }
            return state.subscribers
        }
        for subscriber in subscribers { subscriber.yield(change) }
    }
}
