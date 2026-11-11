import Dispatch
import Foundation
import HFRModels
@testable import HFRStorage
import Synchronization
import Testing

extension Harness {
    /// The importer over this harness, with the erased-accounts list `erased` (LOT-157).
    func importer(erased: any ErasedAccountStore, pending: LegacyPendingStore? = nil) -> LegacyImporter {
        let source = accountsFailure.map { InMemoryLegacyAccountSource(failing: $0) } ?? InMemoryLegacyAccountSource(accounts)
        let container = LegacyContainer(
            documentsDirectory: documents, cachesDirectory: caches, defaults: InMemoryLegacyDefaults(defaults), accounts: source
        )
        var destinations = destinations
        destinations.erasedAccounts = erased
        if let pending { destinations.pending = pending }
        return LegacyImporter(container: container, destinations: destinations, state: statePersistence)
    }
}

@Suite("Legacy import and the accounts erased from the device (LOT-157)")
struct LegacyImporterErasedTests {
    private let now = Date(timeIntervalSinceReferenceDate: 725_800_000)

    @Test("an erased account, its legacy blocklist and the global items it would receive are not imported, nor moved")
    func erasedAccountStaysErased() async throws {
        let harness = try Harness.full()
        defer { harness.remove() }
        let erased = InMemoryErasedAccountStore()
        // `fakeuser2` is legacy's main account, and its blocklist is keyed by its display name "FakeUser2".
        try erased.insert("fakeuser2")

        let report = await harness.importer(erased: erased).run(currentAccount: "fakeuser1", now: now)

        #expect(report.isComplete)
        #expect(report.outcomes[.accounts] == .imported(1))
        #expect(try harness.credentials.load().accounts.map(\.pseudo) == ["fakeuser1"])
        let lists = harness.destinations.pseudoLists
        #expect(await lists.blocklist(for: "fakeuser2").isEmpty)
        #expect(await lists.blocklist(for: "FakeUser2").isEmpty)
        #expect(await lists.blocklist(for: "ghost").map(\.pseudo) == ["fakeblocked2"])
        for account in ["fakeuser1", "fakeuser2"] {
            #expect(await harness.destinations.pending.pendingSuperFavorites(for: account).isEmpty)
            #expect(await harness.destinations.pending.pendingReplyDrafts(for: account).isEmpty)
            #expect(await harness.destinations.smileyFavorites.favorites(for: account).isEmpty)
            #expect(await harness.destinations.drafts.draft(for: .legacyGlobal, account: account) == nil)
        }
        // Items of no account are still imported.
        #expect(report.outcomes[.collapsedSections] == .imported(3))
    }

    @Test("an account erased before the import ran is skipped by the next run")
    func forgetBeforeTheImport() async throws {
        var harness = try Harness.full()
        defer { harness.remove() }
        let erased = InMemoryErasedAccountStore()
        harness.accountsFailure = .sourceUnavailable
        let first = await harness.importer(erased: erased).run(now: now)
        #expect(first.outcomes[.accounts] == .failed(.sourceUnavailable))

        try await harness.importer(erased: erased).forget(account: " FakeUser1 ")
        #expect(try erased.keys() == ["fakeuser1"])

        harness.accountsFailure = nil
        _ = await harness.importer(erased: erased).run(now: now)
        #expect(try harness.credentials.load().accounts.map(\.pseudo) == ["fakeuser2"])
    }

    @Test("once the import is complete, only an account the legacy Keychain still lists is recorded")
    func forgetAfterACompleteImport() async throws {
        let harness = try Harness.full()
        defer { harness.remove() }
        let erased = InMemoryErasedAccountStore()
        let importer = harness.importer(erased: erased)
        #expect(await importer.run(now: now).isComplete)

        try await importer.forget(account: "newuser")
        #expect(try erased.keys().isEmpty)
        try await importer.forget(account: "FAKEUSER1")
        #expect(try erased.keys() == ["fakeuser1"])
    }

    @Test("an unreadable list holds back every step that writes for an account, and nothing else")
    func unreadableListWaits() async throws {
        let harness = try Harness.full()
        defer { harness.remove() }
        let erased = InMemoryErasedAccountStore(envelope: Data("not json".utf8))

        let report = await harness.importer(erased: erased).run(currentAccount: "fakeuser1", now: now)

        #expect(report.outcomes[.accounts] == .failed(.sourceUnavailable))
        #expect(report.outcomes[.pseudoLists] == .waitingForAccount)
        #expect(report.outcomes[.collapsedSections] == .imported(3))
        #expect(try harness.credentials.load().accounts.isEmpty)
        #expect(await harness.destinations.pseudoLists.allowlist().isEmpty)
    }

    @Test("a list written by a newer version is neither read as empty nor overwritten")
    func newerListIsKept() throws {
        let newer = Data(#"{"keys":[],"version":2}"#.utf8)
        let store = InMemoryErasedAccountStore(envelope: newer)
        #expect(throws: CredentialStoreError.unsupportedVersion(2)) { try store.keys() }
        #expect(throws: CredentialStoreError.unsupportedVersion(2)) { try store.insert("fakeuser1") }
        let keys = try InMemoryErasedAccountStore(envelope: try ErasedAccountsEnvelope.encode(["a"])).keys()
        #expect(keys == ["a"])
    }

    @Test("a blocklist keyed by an erased account's legacy display name, unlike its pseudo, is not brought back")
    func erasedDisplayNameList() async throws {
        var harness = try Harness()
        defer { harness.remove() }
        harness.accounts = [LegacyAccountRecord(
            pseudo: "fake%20user3", displayName: "fake user3", cookies: [Harness.cookie("md_user", "fake%20user3")], isMain: true
        )]
        let renamed = blocklistPlist.replacingOccurrences(of: "<key>FakeUser2</key>", with: "<key>fake user3</key>")
        try harness.write(renamed, to: LegacyKeys.blocklistFile)
        let erased = InMemoryErasedAccountStore()
        try erased.insert("fake%20user3")

        let report = await harness.importer(erased: erased).run(now: now)

        #expect(report.outcomes[.pseudoLists] == .imported(1))
        let lists = harness.destinations.pseudoLists
        #expect(await lists.blocklist(for: "fake user3").isEmpty)
        #expect(await lists.blocklist(for: "fake%20user3").isEmpty)
        #expect(await lists.blocklist(for: "ghost").map(\.pseudo) == ["fakeblocked2"])
    }

    @Test("with an erased account, unreadable legacy accounts hold the blocklist step back")
    func unreadableLegacyAccountsHoldListsBack() async throws {
        var harness = try Harness()
        defer { harness.remove() }
        try harness.write(blocklistPlist, to: LegacyKeys.blocklistFile)
        try harness.statePersistence.save(LegacyImportStateDocument(done: [.accounts]))
        harness.accountsFailure = .sourceUnavailable
        let erased = InMemoryErasedAccountStore()
        try erased.insert("fakeuser2")

        let report = await harness.importer(erased: erased).run(now: now)

        #expect(report.outcomes[.pseudoLists] == .failed(.sourceUnavailable))
        #expect(await harness.destinations.pseudoLists.blocklist(for: "FakeUser2").isEmpty)
        #expect(harness.statePersistence.document?.done.contains(.pseudoLists) == false)
    }

    @Test("forget waits for the run in progress: that run keeps the list it read, the next one skips the account")
    func forgetIsSerializedWithARun() async throws {
        let harness = try Harness.full()
        defer { harness.remove() }
        let gate = SaveGate()
        let pending = LegacyPendingStore(persistence: GatedPersistence<LegacyPendingDocument>(gate: gate))
        let erased = InMemoryErasedAccountStore()
        let importer = harness.importer(erased: erased, pending: pending)

        // The run stops inside the super-favourites step, after the accounts step read the (empty) list.
        let run = Task { await importer.run(now: now) }
        try await gate.waitUntilEntered()
        let forget = Task { try await importer.forget(account: "fakeuser1") }
        try await Task.sleep(for: .milliseconds(200))
        #expect(try erased.keys().isEmpty)

        gate.open()
        #expect(await run.value.outcomes[.accounts] == .imported(2))
        try await forget.value
        #expect(try erased.keys() == ["fakeuser1"])
    }

    @Test("a list with a version below 1 is not a list")
    func versionZeroIsCorrupted() {
        let store = InMemoryErasedAccountStore(envelope: Data(#"{"keys":["a"],"version":0}"#.utf8))
        #expect(throws: CredentialStoreError.corrupted) { try store.keys() }
    }
}

/// Holds the first save of a persistence until `open()`, so a test can act while an import run is suspended in it.
final class SaveGate: Sendable {
    private let entered = Mutex(false)
    private let semaphore = DispatchSemaphore(value: 0)

    /// Called by the persistence: marks the save as reached, then waits (at most 5 s, so a test never hangs).
    func pass() {
        let first = entered.withLock { reached in
            defer { reached = true }
            return !reached
        }
        if first { _ = semaphore.wait(timeout: .now() + 5) }
    }

    func open() {
        semaphore.signal()
    }

    func waitUntilEntered() async throws {
        for _ in 0..<500 where !entered.withLock({ $0 }) {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(entered.withLock { $0 })
    }
}

/// An in-memory persistence whose first save waits on `gate`.
final class GatedPersistence<Document: SmallStoreDocument>: SmallStorePersistence {
    private let inner = InMemorySmallStorePersistence<Document>()
    private let gate: SaveGate

    init(gate: SaveGate) {
        self.gate = gate
    }

    func load() throws -> Document? { try inner.load() }

    func save(_ document: Document) throws {
        gate.pass()
        try inner.save(document)
    }

    func quarantineUnreadableData() throws { try inner.quarantineUnreadableData() }
}
