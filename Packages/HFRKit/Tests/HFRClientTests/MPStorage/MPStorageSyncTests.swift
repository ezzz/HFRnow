import Foundation
import HFRModels
import Testing
@testable import HFRClient

/// The per-account sync loop (LOT-130): detection, sync with and without local edits, creation, local-first edits, and the
/// rule that a failure never drops a local edit. The forum side is scripted: no session, no request.
struct MPStorageSyncTests {
    typealias Fixture = MPStorageSyncFixture
    static let post = MPStorageCapture.post

    static func make(
        _ copy: MPStorageSyncCopy = MPStorageSyncCopy(), remote: ScriptedMPStorageRemote
    ) -> (MPStorageSync, InMemoryMPStorageSyncPersistence) {
        let persistence = InMemoryMPStorageSyncPersistence(copy)
        return (MPStorageSync(remote: remote, persistence: persistence), persistence)
    }

    // MARK: Detection

    @Test func detectionReadsTheCachedThreadWithoutSearching() async throws {
        let remote = ScriptedMPStorageRemote(reads: [.success(try Fixture.snapshot(blocking: ["user1"]))])
        let (sync, persistence) = Self.make(MPStorageSyncCopy(post: Self.post), remote: remote)
        #expect(try await sync.detect(now: Fixture.now) == .found)
        #expect(await remote.calls == [.read(Self.post)])
        let stored = await persistence.stored
        #expect(stored.base == (try Fixture.text(blocking: ["user1"])))
        #expect(stored.lastSync == Fixture.now)
    }

    @Test func aStaleCachedThreadIsSearchedAgain() async throws {
        let remote = ScriptedMPStorageRemote(
            finds: [.success(42)], reads: [.failure(.notAddressed), .success(try Fixture.snapshot(post: 42))]
        )
        let (sync, persistence) = Self.make(MPStorageSyncCopy(post: Self.post), remote: remote)
        #expect(try await sync.detect(now: Fixture.now) == .found)
        #expect(await remote.calls == [.read(Self.post), .find, .read(42)])
        #expect(await persistence.stored.post == 42)
    }

    @Test func noThreadInTheListIsNotFoundAndDated() async throws {
        let remote = ScriptedMPStorageRemote(finds: [.success(nil)])
        let (sync, persistence) = Self.make(remote: remote)
        #expect(try await sync.detect(now: Fixture.now) == .notFound)
        let stored = await persistence.stored
        #expect(stored.lastSearch == Fixture.now)
        #expect(stored.base == nil)
        #expect(stored.lastSync == nil)
    }

    @Test func aSearchThatStopsAtItsLimitIsAFailureNeverNotFound() async throws {
        let remote = ScriptedMPStorageRemote(finds: [.failure(.searchLimitReached(pages: 50))])
        let (sync, persistence) = Self.make(remote: remote)
        await #expect(throws: MPStorageSyncError.transport(.searchLimitReached(pages: 50))) {
            try await sync.detect(now: Fixture.now)
        }
        #expect(await persistence.stored.lastSearch == nil)
    }

    @Test func detectionKeepsTheBaseOfPendingEdits() async throws {
        let base = try Fixture.text()
        let pending = try Fixture.text(blocking: ["user9"])
        let remote = ScriptedMPStorageRemote(reads: [.success(try Fixture.snapshot(blocking: ["user1"]))])
        let (sync, persistence) = Self.make(MPStorageSyncCopy(post: Self.post, base: base, pending: pending), remote: remote)
        #expect(try await sync.detect(now: Fixture.now) == .found)
        let stored = await persistence.stored
        #expect(stored.base == base)
        #expect(stored.pending == pending)
    }

    // MARK: Sync

    @Test func aSyncWithoutEditsTakesTheForumCopyAsBase() async throws {
        let remote = ScriptedMPStorageRemote(reads: [.success(try Fixture.snapshot(blocking: ["user2"]))])
        let (sync, persistence) = Self.make(MPStorageSyncCopy(post: Self.post, base: try Fixture.text()), remote: remote)
        #expect(try await sync.sync(now: Fixture.now) == .synced(wrote: false))
        let stored = await persistence.stored
        #expect(stored.base == (try Fixture.text(blocking: ["user2"])))
        #expect(stored.lastSync == Fixture.now)
        #expect(await remote.calls == [.read(Self.post)])
    }

    @Test func pendingEditsAreWrittenOnTheStoredBaseThenCleared() async throws {
        let base = try Fixture.text()
        let pending = try Fixture.text(blocking: ["user9"])
        let remote = ScriptedMPStorageRemote(
            reads: [.success(try Fixture.snapshot(blocking: ["user2"]))],
            saves: [.success(try Fixture.saved(blocking: ["user2", "user9"]))]
        )
        let (sync, persistence) = Self.make(MPStorageSyncCopy(post: Self.post, base: base, pending: pending), remote: remote)
        #expect(try await sync.sync(now: Fixture.now) == .synced(wrote: true))
        // The merge base is the copy the edits were made on, not the one just read (LOT-062).
        #expect(await remote.calls == [.read(Self.post), .save(ours: pending, base: base, post: Self.post)])
        let stored = await persistence.stored
        #expect(stored.pending == nil)
        #expect(stored.base == (try Fixture.text(blocking: ["user2", "user9"])))
        #expect(stored.lastSync == Fixture.now)
    }

    @Test(arguments: [
        MPStorageTransportError.network(.offline),
        .posting(.unconfirmed(.transport(.timedOut))),
        .posting(.rejected(message: nil)),
        .document(.tooLarge(byteCount: 70_000, limit: 65_536))
    ])
    func aFailedWriteKeepsTheLocalEdits(_ failure: MPStorageTransportError) async throws {
        let base = try Fixture.text()
        let pending = try Fixture.text(blocking: ["user9"])
        let remote = ScriptedMPStorageRemote(reads: [.success(try Fixture.snapshot())], saves: [.failure(failure)])
        let (sync, persistence) = Self.make(MPStorageSyncCopy(post: Self.post, base: base, pending: pending), remote: remote)
        await #expect(throws: MPStorageSyncError.transport(failure)) { try await sync.sync(now: Fixture.now) }
        let stored = await persistence.stored
        #expect(stored.pending == pending)
        #expect(stored.base == base)
        #expect(stored.lastSync == nil)
    }

    @Test func aConcurrentWriteSeenByTheReadBackIsMergedOnceMore() async throws {
        let pending = try Fixture.text(blocking: ["user9"])
        let remote = ScriptedMPStorageRemote(
            reads: [.success(try Fixture.snapshot())],
            saves: [.failure(.notVerified(readBack: nil)), .success(try Fixture.saved(blocking: ["user8", "user9"]))]
        )
        let (sync, persistence) = Self.make(MPStorageSyncCopy(post: Self.post, base: try Fixture.text(), pending: pending), remote: remote)
        #expect(try await sync.sync(now: Fixture.now) == .synced(wrote: true))
        #expect(await remote.calls.count == 3)
        #expect(await persistence.stored.pending == nil)
    }

    @Test func aSecondUnverifiedWriteIsReportedAndKeepsTheEdits() async throws {
        let pending = try Fixture.text(blocking: ["user9"])
        let remote = ScriptedMPStorageRemote(
            reads: [.success(try Fixture.snapshot())],
            saves: [.failure(.notVerified(readBack: nil)), .failure(.notVerified(readBack: nil))]
        )
        let (sync, persistence) = Self.make(MPStorageSyncCopy(post: Self.post, base: try Fixture.text(), pending: pending), remote: remote)
        await #expect(throws: MPStorageSyncError.transport(.notVerified(readBack: nil))) { try await sync.sync(now: Fixture.now) }
        #expect(await remote.calls.count == 3)
        #expect(await persistence.stored.pending == pending)
    }

    @Test func noThreadWritesNothingAndKeepsTheEdits() async throws {
        let pending = try Fixture.text(blocking: ["user9"])
        let remote = ScriptedMPStorageRemote(finds: [.success(nil)], reads: [.failure(.notAddressed)])
        let (sync, persistence) = Self.make(MPStorageSyncCopy(post: Self.post, base: try Fixture.text(), pending: pending), remote: remote)
        #expect(try await sync.sync(now: Fixture.now) == .noThread)
        #expect(await remote.calls == [.read(Self.post), .find])
        let stored = await persistence.stored
        #expect(stored.post == nil)
        #expect(stored.pending == pending)
    }

    @Test func aFailedReadKeepsTheThreadFoundBeforeIt() async throws {
        let remote = ScriptedMPStorageRemote(finds: [.success(42)], reads: [.failure(.network(.offline))])
        let (sync, persistence) = Self.make(remote: remote)
        await #expect(throws: MPStorageSyncError.transport(.network(.offline))) { try await sync.sync(now: Fixture.now) }
        #expect(await persistence.stored.post == 42)
    }

    @Test func anUnsavedCopyIsReported() async throws {
        let remote = ScriptedMPStorageRemote(reads: [.success(try Fixture.snapshot())])
        let (sync, persistence) = Self.make(MPStorageSyncCopy(post: Self.post), remote: remote)
        await persistence.failSaves()
        await #expect(throws: MPStorageSyncError.storage(reason: "disk full")) { try await sync.sync(now: Fixture.now) }
    }

    // MARK: Creation

    @Test func creationStoresTheNewThread() async throws {
        let remote = ScriptedMPStorageRemote(creations: [.success(.created(try Fixture.snapshot(post: 42)))])
        let (sync, persistence) = Self.make(MPStorageSyncCopy(lastSearch: Fixture.now), remote: remote)
        try await sync.create(now: Fixture.now)
        #expect(await remote.calls == [.create])
        let stored = await persistence.stored
        #expect(stored.post == 42)
        #expect(stored.base == (try Fixture.text()))
        #expect(stored.lastSearch == nil)
        #expect(stored.lastSync == Fixture.now)
    }

    @Test func creationThenWritesThePendingEdits() async throws {
        let base = try Fixture.text()
        let pending = try Fixture.text(blocking: ["user9"])
        let remote = ScriptedMPStorageRemote(
            reads: [.success(try Fixture.snapshot())],
            saves: [.success(try Fixture.saved(blocking: ["user9"]))],
            creations: [.success(.existing(try Fixture.snapshot()))]
        )
        let (sync, persistence) = Self.make(MPStorageSyncCopy(base: base, pending: pending), remote: remote)
        try await sync.create(now: Fixture.now)
        #expect(await remote.calls == [.create, .read(Self.post), .save(ours: pending, base: base, post: Self.post)])
        #expect(await persistence.stored.pending == nil)
    }

    @Test func aFailedCreationChangesNothing() async throws {
        let remote = ScriptedMPStorageRemote(creations: [.failure(.posting(.rejected(message: nil)))])
        let (sync, persistence) = Self.make(remote: remote)
        await #expect(throws: MPStorageSyncError.transport(.posting(.rejected(message: nil)))) {
            try await sync.create(now: Fixture.now)
        }
        #expect(await persistence.stored == MPStorageSyncCopy())
    }

    // MARK: Edits

    @Test func anEditIsLocalFirst() async throws {
        let remote = ScriptedMPStorageRemote()
        let (sync, persistence) = Self.make(MPStorageSyncCopy(post: Self.post, base: try Fixture.text()), remote: remote)
        let changed = try await sync.edit(now: Fixture.now) { document, stamp in
            try document.addBlocklistEntry(username: "user9", stamp: stamp)
        }
        #expect(changed)
        #expect(await remote.calls.isEmpty)
        let pending = try MPStorageCodec.decode(try #require(await persistence.stored.pending))
        #expect(pending.data.first?.blocklist?.list.map(\.username) == ["user9"])
    }

    @Test func aSecondEditBuildsOnTheFirst() async throws {
        let (sync, persistence) = Self.make(MPStorageSyncCopy(post: Self.post, base: try Fixture.text()), remote: ScriptedMPStorageRemote())
        for name in ["user8", "user9"] {
            _ = try await sync.edit(now: Fixture.now) { document, stamp in try document.addBlocklistEntry(username: name, stamp: stamp) }
        }
        let pending = try MPStorageCodec.decode(try #require(await persistence.stored.pending))
        #expect(pending.data.first?.blocklist?.list.map(\.username) == ["user9", "user8"])
    }

    @Test func anEditThatChangesNothingStoresNothing() async throws {
        let (sync, persistence) = Self.make(
            MPStorageSyncCopy(post: Self.post, base: try Fixture.text(blocking: ["user9"])), remote: ScriptedMPStorageRemote()
        )
        let changed = try await sync.edit(now: Fixture.now) { document, stamp in
            try document.addBlocklistEntry(username: "USER9", stamp: stamp)
        }
        #expect(!changed)
        #expect(await persistence.stored.pending == nil)
        #expect(await persistence.saveCount == 0)
    }

    @Test func anEditBeforeAnyReadIsRefused() async throws {
        let (sync, _) = Self.make(remote: ScriptedMPStorageRemote())
        await #expect(throws: MPStorageSyncError.notLoaded) {
            try await sync.edit(now: Fixture.now) { document, stamp in try document.addBlocklistEntry(username: "user9", stamp: stamp) }
        }
    }

    @Test func aRefusedEditStoresNothing() async throws {
        let (sync, persistence) = Self.make(MPStorageSyncCopy(post: Self.post, base: try Fixture.text()), remote: ScriptedMPStorageRemote())
        do {
            _ = try await sync.edit(now: Fixture.now) { document, stamp in
                try document.addBlocklistEntry(username: "user\u{1F600}", stamp: stamp)
            }
            Issue.record("expected a refusal")
        } catch {
            guard case .document(.nonBMPCharacter) = error else {
                Issue.record("expected a non-BMP refusal, got \(error)")
                return
            }
        }
        #expect(await persistence.stored.pending == nil)
    }

    @Test func anEditWaitsForTheSyncInFlight() async throws {
        let remote = ScriptedMPStorageRemote(reads: [.success(try Fixture.snapshot(blocking: ["user2"]))])
        await remote.hold()
        let (sync, persistence) = Self.make(MPStorageSyncCopy(post: Self.post, base: try Fixture.text()), remote: remote)
        let syncing = Task { try await sync.sync(now: Fixture.now) }
        await remote.waitUntilHeld()
        let editing = Task {
            try await sync.edit(now: Fixture.now) { document, stamp in try document.addBlocklistEntry(username: "user9", stamp: stamp) }
        }
        // Time for the edit to run if nothing queued it: without the queue it would store its edit now, then the sync would
        // save the copy it loaded before, dropping the edit.
        for _ in 0..<200 { await Task.yield() }
        #expect(await persistence.stored.pending == nil)
        await remote.release()
        #expect(try await syncing.value == .synced(wrote: false))
        #expect(try await editing.value)
        let stored = await persistence.stored
        // Made after the sync, on the copy it read: the sync's base update cannot drop it.
        #expect(stored.base == (try Fixture.text(blocking: ["user2"])))
        let pending = try MPStorageCodec.decode(try #require(stored.pending))
        #expect(pending.data.first?.blocklist?.list.map(\.username) == ["user9", "user2"])
    }

    // MARK: Flags

    @Test func theFlagOfAThreadIsReadFromTheWritableEntry() async throws {
        let flag = MPStorageMPFlag(topic: 77, pValue: "1", href: "t123", page: 4)
        let document = try Fixture.document(flags: [flag, MPStorageMPFlag(topic: 78, page: 2)])
        #expect(MPStorageSync.flag(forThread: 77, in: document) == flag)
        #expect(MPStorageSync.flag(forThread: 79, in: document) == nil)
        let (sync, _) = Self.make(
            MPStorageSyncCopy(post: Self.post, base: try MPStorageCodec.encodeForWriting(document)), remote: ScriptedMPStorageRemote()
        )
        #expect(try await sync.document() == document)
    }
}
