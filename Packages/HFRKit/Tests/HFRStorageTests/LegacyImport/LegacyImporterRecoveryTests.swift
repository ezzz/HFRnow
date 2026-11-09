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
}
