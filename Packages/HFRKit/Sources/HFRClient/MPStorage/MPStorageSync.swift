import Foundation
import HFRModels

/// One account's MPStorage sync loop (LOT-130, ADR 0013 §2, §4, §7): the device copy is the read model, edits are local
/// first and written on the next sync, a remote read becomes the merge base, and a failure never drops a local edit.
///
/// It never reads the account's sync state: the app calls `sync` and `edit` only while the state is `on`, `detect` while it
/// is `unasked`, and `create` once the member agreed. Calls run one at a time, in the order they were made, so an edit
/// never lands inside a sync's read-merge-write; each call saves the copy once, before it returns or throws.
public actor MPStorageSync {
    private let remote: any MPStorageRemote
    private let persistence: any MPStorageSyncPersistence
    private let sourceName: String
    /// The last call queued; the next one waits for it.
    private var tail: Task<Void, Never>?

    /// Creates the loop over the forum side and the device copy. `sourceName` is stamped on what this app writes.
    public init(
        remote: any MPStorageRemote, persistence: any MPStorageSyncPersistence,
        sourceName: String = MPStorageStamp.legacySourceName
    ) {
        self.remote = remote
        self.persistence = persistence
        self.sourceName = sourceName
    }

    // MARK: Reading

    /// The device copy, after the calls already queued.
    public func copy() async throws(MPStorageSyncError) -> MPStorageSyncCopy {
        try await serialized { sync throws(MPStorageSyncError) in try await sync.persistence.load() }
    }

    /// The document the app shows (`MPStorageSyncCopy.currentText`), decoded; nil before the first read.
    /// - Throws: `unreadableCopy` when the stored text is not a document, and the copy's `storage` errors.
    public func document() async throws(MPStorageSyncError) -> MPStorageDocument? {
        try Self.decode(try await copy().currentText)
    }

    /// The `mpFlags` item of conversation `post` in `document` (legacy `getUrlFlagForTopidId:`, `MPStorage.m:527-565` @
    /// 87fe0d1c): the writable entry's, the first with that number.
    nonisolated public static func flag(forThread post: Int, in document: MPStorageDocument) -> MPStorageMPFlag? {
        guard let index = document.writableEntryIndex else { return nil }
        return document.data[index].mpFlags?.list.first { $0.topic == post }
    }

    // MARK: Calls

    /// Looks for the account's storage thread without writing anything (ADR 0013 §7, "found → on"): the cached thread
    /// first, then the MP list. Found, its document becomes the copy's base (unless local edits wait, which keep theirs);
    /// not found, `lastSearch` is `now`.
    public func detect(now: Date) async throws(MPStorageSyncError) -> MPStorageDetection {
        try await serialized { sync throws(MPStorageSyncError) in try await sync.performDetect(now: now) }
    }

    /// Reads the forum copy and writes the local edits, merged (LOT-052). See the type's rules.
    public func sync(now: Date) async throws(MPStorageSyncError) -> MPStorageSyncOutcome {
        try await serialized { sync throws(MPStorageSyncError) in try await sync.performSync(now: now) }
    }

    /// Creates the storage thread (the member agreed), unless one exists, then writes the pending edits if any.
    public func create(now: Date) async throws(MPStorageSyncError) {
        try await serialized { sync throws(MPStorageSyncError) in try await sync.performCreate(now: now) }
    }

    /// Applies `change` (a LOT-062 edit) to the document the app shows and stores the result as the pending edits;
    /// nothing is sent (call `sync`). Returns false, and stores nothing, when `change` changed nothing.
    /// - Throws: `notLoaded` before the first read, `document` when the edit or the edited document is refused.
    public func edit(
        now: Date, _ change: @escaping @Sendable (inout MPStorageDocument, MPStorageStamp) throws -> Bool
    ) async throws(MPStorageSyncError) -> Bool {
        try await serialized { sync throws(MPStorageSyncError) in try await sync.performEdit(now: now, change) }
    }

    // MARK: Steps

    private func performDetect(now: Date) async throws(MPStorageSyncError) -> MPStorageDetection {
        var copy = try await persistence.load()
        do throws(MPStorageSyncError) {
            guard let snapshot = try await locate(&copy) else {
                copy.lastSearch = now
                try await persistence.save(copy)
                return .notFound
            }
            adopt(snapshot, into: &copy, now: now)
            try await persistence.save(copy)
            return .found
        } catch {
            throw await failing(error, keeping: copy)
        }
    }

    private func performSync(now: Date) async throws(MPStorageSyncError) -> MPStorageSyncOutcome {
        var copy = try await persistence.load()
        do throws(MPStorageSyncError) {
            guard let snapshot = try await locate(&copy) else {
                try await persistence.save(copy)
                return .noThread
            }
            var wrote = false
            if let pendingText = copy.pending {
                guard let ours = try Self.decode(pendingText) else { throw .unreadableCopy }
                let base = try? Self.decode(copy.base)
                let result = try await write(ours, base: base, at: snapshot.location, now: now)
                wrote = result.wrote
                copy.base = result.snapshot.text
                copy.pending = nil
                copy.lastSync = now
            } else {
                adopt(snapshot, into: &copy, now: now)
            }
            try await persistence.save(copy)
            return .synced(wrote: wrote)
        } catch {
            throw await failing(error, keeping: copy)
        }
    }

    private func performCreate(now: Date) async throws(MPStorageSyncError) {
        var copy = try await persistence.load()
        do throws(MPStorageSyncError) {
            let snapshot: MPStorageSnapshot
            do throws(MPStorageTransportError) {
                snapshot = try await remote.create(stamp: stamp(now)).snapshot
            } catch {
                throw .transport(error)
            }
            copy.post = snapshot.location.post
            copy.lastSearch = nil
            adopt(snapshot, into: &copy, now: now)
            try await persistence.save(copy)
        } catch {
            throw await failing(error, keeping: copy)
        }
        if copy.pending != nil { _ = try await performSync(now: now) }
    }

    private func performEdit(
        now: Date, _ change: (inout MPStorageDocument, MPStorageStamp) throws -> Bool
    ) async throws(MPStorageSyncError) -> Bool {
        var copy = try await persistence.load()
        guard let current = try Self.decode(copy.currentText) else { throw .notLoaded }
        var edited = current
        let text: String
        do {
            guard try change(&edited, stamp(now)) else { return false }
            text = try MPStorageCodec.encodeForWriting(edited)
        } catch let error as MPStorageError {
            throw .document(error)
        } catch {
            throw .unreadableCopy
        }
        copy.pending = text
        try await persistence.save(copy)
        return true
    }

    /// The forum copy: the cached thread, or, when it is unknown or no longer this account's (`notAddressed`), the thread
    /// the MP list shows, cached in `copy`. Nil when the list ends without one (the cached id is then dropped).
    private func locate(_ copy: inout MPStorageSyncCopy) async throws(MPStorageSyncError) -> MPStorageSnapshot? {
        do throws(MPStorageTransportError) {
            if let post = copy.post {
                do throws(MPStorageTransportError) {
                    return try await remote.read(post: post)
                } catch .notAddressed {
                    copy.post = nil
                }
            }
            guard let post = try await remote.findThread() else { return nil }
            copy.post = post
            copy.lastSearch = nil
            return try await remote.read(post: post)
        } catch {
            throw .transport(error)
        }
    }

    /// LOT-052's save; a concurrent write between its merge and its read-back (`notVerified(readBack: nil)`) is merged
    /// once more with the copy stored then.
    private func write(
        _ ours: MPStorageDocument, base: MPStorageDocument?, at location: MPStorageLocation, now: Date
    ) async throws(MPStorageSyncError) -> MPStorageSaveResult {
        do throws(MPStorageTransportError) {
            do throws(MPStorageTransportError) {
                return try await remote.save(ours, base: base, at: location, stamp: stamp(now))
            } catch .notVerified(readBack: nil) {
                return try await remote.save(ours, base: base, at: location, stamp: stamp(now))
            }
        } catch {
            throw .transport(error)
        }
    }

    /// The forum copy read becomes the base, unless local edits wait: they were made on the stored base, which must stay
    /// their merge base until they are written.
    private func adopt(_ snapshot: MPStorageSnapshot, into copy: inout MPStorageSyncCopy, now: Date) {
        copy.post = snapshot.location.post
        if copy.pending == nil { copy.base = snapshot.text }
        copy.lastSync = now
    }

    /// Saves what the failed call learnt (the thread id), then gives the call's error; a failed save is reported only when
    /// the call itself had no other error to give.
    private func failing(_ error: MPStorageSyncError, keeping copy: MPStorageSyncCopy) async -> MPStorageSyncError {
        if case .storage = error { return error }
        do {
            try await persistence.save(copy)
        } catch {
            // The call's own error says more.
        }
        return error
    }

    private func stamp(_ now: Date) -> MPStorageStamp {
        MPStorageStamp(sourceName: sourceName, date: now)
    }

    private static func decode(_ text: String?) throws(MPStorageSyncError) -> MPStorageDocument? {
        guard let text else { return nil }
        do {
            return try MPStorageCodec.decode(text)
        } catch {
            throw .unreadableCopy
        }
    }

    /// Runs `work` after every call queued before it, so calls never interleave across their suspension points.
    private func serialized<Value: Sendable>(
        _ work: @escaping @Sendable (MPStorageSync) async throws(MPStorageSyncError) -> Value
    ) async throws(MPStorageSyncError) -> Value {
        let previous = tail
        let task = Task { () async -> Result<Value, MPStorageSyncError> in
            await previous?.value
            do throws(MPStorageSyncError) {
                return .success(try await work(self))
            } catch {
                return .failure(error)
            }
        }
        tail = Task { _ = await task.value }
        return try await task.value.get()
    }
}
