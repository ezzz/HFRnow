import Foundation
import HFRModels
@testable import HFRStorage
import Testing

extension Harness {
    /// The importer over this harness, with the erased-accounts list `erased` (LOT-157).
    func importer(erased: any ErasedAccountStore) -> LegacyImporter {
        let source = accountsFailure.map { InMemoryLegacyAccountSource(failing: $0) } ?? InMemoryLegacyAccountSource(accounts)
        let container = LegacyContainer(
            documentsDirectory: documents, cachesDirectory: caches, defaults: InMemoryLegacyDefaults(defaults), accounts: source
        )
        var destinations = destinations
        destinations.erasedAccounts = erased
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
}
