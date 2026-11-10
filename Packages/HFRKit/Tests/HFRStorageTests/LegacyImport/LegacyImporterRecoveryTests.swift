import Foundation
import HFRModels
@testable import HFRStorage
import Testing

@Suite("Legacy importer, review round 1 (LOT-067)")
struct LegacyImporterRecoveryTests {
    private let now = Date(timeIntervalSinceReferenceDate: 725_800_000)

    @Test("the pseudo lists wait for the accounts step, so a list keyed by a display name finds its account")
    func pseudoListsWaitForAccounts() async throws {
        var harness = try Harness()
        defer { harness.remove() }
        harness.accounts = [LegacyAccountRecord(
            pseudo: "fake%20user3", displayName: "fake user3", cookies: [Harness.cookie("md_user", "fake%20user3")], isMain: true
        )]
        let renamed = blocklistPlist.replacingOccurrences(of: "<key>FakeUser2</key>", with: "<key>fake user3</key>")
        try harness.write(renamed, to: LegacyKeys.blocklistFile)
        harness.accountsFailure = .sourceUnavailable
        let first = await harness.importer().run(now: now)
        #expect(first.outcomes[.pseudoLists] == .waitingForAccount)

        harness.accountsFailure = nil
        _ = await harness.importer().run(now: now)
        #expect(await harness.destinations.pseudoLists.blocklist(for: "fake%20user3").map(\.pseudo) == ["fakeblocked1"])
        #expect(await harness.destinations.pseudoLists.blocklist(for: "fake user3").isEmpty)
    }

    @Test("a smiley favourite with a blank code is rejected alone; the later ones are imported")
    func blankSmileyCode() async throws {
        var harness = try Harness()
        defer { harness.remove() }
        harness.accounts = Harness.legacyAccounts
        // The oldest favourite's code, an ASCII string in the archive, overwritten in place by spaces of the same length.
        var archive = try LegacySamples.data("smiley-favorites-typical.archive")
        let code = Data("[:fake1]".utf8)
        let range = try #require(archive.range(of: code))
        archive.replaceSubrange(range, with: Data(repeating: 0x20, count: code.count))
        try archive.write(to: harness.documents.appending(path: LegacyKeys.smileyFavoritesFile))
        let report = await harness.importer().run(now: now)
        #expect(report.outcomes[.smileyFavorites] == .imported(2))
        #expect(report.rejectedItems == 1)
        #expect(await harness.destinations.smileyFavorites.favorites(for: "fakeuser2").map(\.code) == ["[:fake2]", "[:fake3:2]"])
    }

    @Test("the MPStorage switch is kept in the import state: every later report still gives it")
    func mpStorageSwitchKept() async throws {
        let harness = try Harness.full()
        defer { harness.remove() }
        _ = await harness.importer().run(now: now)
        let second = await harness.importer().run(now: now)
        #expect(second.outcomes[.mpStorageSwitch] == .alreadyDone)
        #expect(second.mpStorageSwitch == .active)
    }

    @Test("overlapping runs are serialized: no run saves over the steps another one did")
    func overlappingRuns() async throws {
        let harness = try Harness.full()
        defer { harness.remove() }
        let importer = harness.importer()
        async let first = importer.run(now: now)
        async let second = importer.run(now: now)
        let reports = await [first, second]
        #expect(reports.contains { $0.isComplete })
        #expect(harness.statePersistence.document?.done == LegacyImportStep.allCases)
        #expect(harness.statePersistence.document?.globalAccount == "fakeuser2")
    }

    @Test("pseudo lists fail, and stay pending, when the stored accounts cannot be read")
    func pseudoListsWhenAccountsUnreadable() async throws {
        let credentials = LoadFailingCredentialStore()
        var harness = try Harness(credentials: InMemoryCredentialStore())
        defer { harness.remove() }
        harness.accounts = Harness.legacyAccounts
        try harness.write(blocklistPlist, to: LegacyKeys.blocklistFile)
        let destinations = LegacyImportDestinations(
            credentials: credentials,
            pseudoLists: harness.destinations.pseudoLists,
            superFavorites: harness.destinations.superFavorites,
            layout: harness.destinations.layout,
            smileyFavorites: harness.destinations.smileyFavorites,
            searchHistory: harness.destinations.searchHistory,
            uploads: harness.destinations.uploads,
            drafts: harness.destinations.drafts,
            pending: harness.destinations.pending,
            settings: harness.destinations.settings
        )
        let container = LegacyContainer(
            documentsDirectory: harness.documents, cachesDirectory: harness.caches,
            defaults: InMemoryLegacyDefaults(), accounts: InMemoryLegacyAccountSource(harness.accounts)
        )
        let report = await LegacyImporter(container: container, destinations: destinations, state: harness.statePersistence).run(now: now)
        #expect(report.outcomes[.accounts] == .imported(2))
        #expect(report.outcomes[.pseudoLists] == .failed(.destinationFailed))
        #expect(await harness.destinations.pseudoLists.blocklist(for: "fakeuser2").isEmpty)
        #expect(harness.statePersistence.document?.done.contains(.pseudoLists) == false)
    }

    @Test("an import state written before the MPStorage switch existed still loads")
    func stateWithoutSwitch() throws {
        let json = Data(#"{"version":1,"importVersion":1,"done":["accounts"],"globalAccount":"fakeuser2"}"#.utf8)
        let state = try JSONDecoder().decode(LegacyImportStateDocument.self, from: json)
        #expect(state.mpStorageSwitch == .notRead)
        #expect(state.done == [.accounts] && state.globalAccount == "fakeuser2")
    }

    @Test("an unreadable allowlist file does not stop a readable blocklist, and the reverse")
    func pseudoListFilesReadOnTheirOwn() async throws {
        var harness = try Harness()
        defer { harness.remove() }
        harness.accounts = Harness.legacyAccounts
        try harness.write(blocklistPlist, to: LegacyKeys.blocklistFile)
        try harness.write("not a plist", to: LegacyKeys.allowlistFile)
        let report = await harness.importer().run(now: now)
        #expect(report.outcomes[.pseudoLists] == .imported(2))
        #expect(await harness.destinations.pseudoLists.blocklist(for: "fakeuser2").map(\.pseudo) == ["fakeblocked1"])

        var reverse = try Harness()
        defer { reverse.remove() }
        reverse.accounts = Harness.legacyAccounts
        try reverse.write("not a plist", to: LegacyKeys.blocklistFile)
        try reverse.write(allowlistPlist, to: LegacyKeys.allowlistFile)
        let reverseReport = await reverse.importer().run(now: now)
        #expect(reverseReport.outcomes[.pseudoLists] == .imported(1))
        #expect(await reverse.destinations.pseudoLists.allowlist().map(\.pseudo) == ["fakeloved1"])
    }
}

/// A credential store whose writes work but whose plain `load()` fails, as a Keychain read refused between two calls.
private final class LoadFailingCredentialStore: CredentialStore, @unchecked Sendable {
    private struct Refused: Error {}
    private let lock = NSLock()
    private var book = AccountBook()

    func load() throws -> AccountBook {
        throw Refused()
    }

    func update<Value>(_ body: (inout AccountBook) throws -> Value) throws -> Value {
        try lock.withLock { try body(&book) }
    }

    func removeAll() throws {
        lock.withLock { book = AccountBook() }
    }
}
