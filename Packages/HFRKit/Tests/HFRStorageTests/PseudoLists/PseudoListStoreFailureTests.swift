import Foundation
import Synchronization
import Testing
@testable import HFRStorage

/// A persistence whose load and save can be made to fail.
private final class FlakyPersistence: PseudoListPersistence {
    struct Failure: Error {}
    private let inner: InMemoryPseudoListPersistence
    let failLoad: Mutex<Bool>
    let failSave: Mutex<Bool>
    let saveCount = Mutex(0)

    init(document: PseudoListDocument?, failLoad: Bool = false, failSave: Bool = false) {
        inner = InMemoryPseudoListPersistence(document)
        self.failLoad = Mutex(failLoad)
        self.failSave = Mutex(failSave)
    }

    var document: PseudoListDocument? { inner.document }

    func load() throws -> PseudoListDocument? {
        if failLoad.withLock({ $0 }) { throw Failure() }
        return try inner.load()
    }

    func save(_ document: PseudoListDocument) throws {
        saveCount.withLock { $0 += 1 }
        if failSave.withLock({ $0 }) { throw Failure() }
        try inner.save(document)
    }

    func quarantineUnreadableData() throws { try inner.quarantineUnreadableData() }
}

@Suite struct PseudoListStoreFailureTests {
    private let existing = PseudoListDocument(
        blocklists: ["me": [PseudoListEntry(pseudo: "Spammer")]],
        allowlist: [PseudoListEntry(pseudo: "Friend")]
    )

    @Test func failedLoadNeverLetsAWriteReplaceTheStoredData() async throws {
        let persistence = FlakyPersistence(document: existing, failLoad: true)
        let store = PseudoListStore(persistence: persistence)
        #expect(await store.blocklist(for: "me").isEmpty)
        await #expect(throws: PseudoListError.self) { try await store.block("New", account: "me") }
        await #expect(throws: PseudoListError.self) { try await store.allow("New") }
        await #expect(throws: PseudoListError.self) { try await store.unblock("Spammer", account: "me") }
        await #expect(throws: PseudoListError.self) { try await store.replaceBlocklist(with: [], account: "me") }
        #expect(persistence.saveCount.withLock { $0 } == 0)
        #expect(persistence.document == existing)
        #expect(await store.loadFailure() != nil)
    }

    @Test func reloadRecoversOnceTheDataIsReadableAgain() async throws {
        let persistence = FlakyPersistence(document: existing, failLoad: true)
        let store = PseudoListStore(persistence: persistence)
        #expect(await store.blocklist(for: "me").isEmpty)
        persistence.failLoad.withLock { $0 = false }
        #expect(await store.reload() == nil)
        #expect(await store.isBlocked("spammer", account: "me"))
        #expect(try await store.block("Other", account: "me"))
        #expect(persistence.document?.blocklists["me"]?.count == 2)
        #expect(persistence.document?.allowlist == existing.allowlist)
    }

    @Test func newerFormatVersionIsReadOnly() async throws {
        let future = PseudoListDocument(version: PseudoListDocument.currentVersion + 1, blocklists: existing.blocklists)
        let persistence = FlakyPersistence(document: future)
        let store = PseudoListStore(persistence: persistence)
        #expect(await store.loadFailure() == .unsupportedVersion(future.version))
        await #expect(throws: PseudoListError.unsupportedVersion(future.version)) { try await store.block("x", account: "me") }
        #expect(persistence.document == future)
    }

    @Test func discardingUnreadableDataStartsFromEmptyListsAndAllowsWrites() async throws {
        let persistence = FlakyPersistence(document: existing, failLoad: true)
        let store = PseudoListStore(persistence: persistence)
        #expect(await store.loadFailure() != nil)
        persistence.failLoad.withLock { $0 = false }
        try await store.discardUnreadableData()
        #expect(await store.loadFailure() == nil)
        #expect(try await store.block("Fresh", account: "me"))
        #expect(persistence.document?.blocklists["me"]?.map(\.pseudo) == ["Fresh"])
    }

    @Test func discardIsANoOpWhenTheStoreIsHealthy() async throws {
        let persistence = FlakyPersistence(document: existing)
        let store = PseudoListStore(persistence: persistence)
        try await store.discardUnreadableData()
        #expect(await store.isBlocked("Spammer", account: "me"))
        #expect(persistence.document == existing)
    }

    @Test func failedSaveLeavesMemoryAndDiskUnchanged() async throws {
        let persistence = FlakyPersistence(document: existing, failSave: true)
        let store = PseudoListStore(persistence: persistence)
        await #expect(throws: PseudoListError.self) { try await store.block("New", account: "me") }
        #expect(await !store.isBlocked("New", account: "me"))
        #expect(persistence.document == existing)
        persistence.failSave.withLock { $0 = false }
        #expect(try await store.block("New", account: "me"))
        #expect(await store.isBlocked("new", account: "me"))
    }
}
