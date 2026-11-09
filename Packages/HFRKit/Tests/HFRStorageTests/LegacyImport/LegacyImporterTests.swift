import Foundation
import HFRModels
@testable import HFRStorage
import Testing

/// A legacy container in a temporary folder and in-memory SwiftHFR stores.
struct Harness {
    let folder: URL
    let documents: URL
    let caches: URL
    let credentials: InMemoryCredentialStore
    let destinations: LegacyImportDestinations
    let statePersistence = InMemorySmallStorePersistence<LegacyImportStateDocument>()
    var defaults: [String: LegacyValue] = [:]
    var accounts: [LegacyAccountRecord] = []
    var accountsFailure: LegacyImportError?

    init(credentials: InMemoryCredentialStore = InMemoryCredentialStore(), settings: [String: SettingRawValue] = [:]) throws {
        folder = try LegacySamples.temporaryFolder()
        documents = folder.appending(path: "Documents", directoryHint: .isDirectory)
        caches = folder.appending(path: "Caches", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        self.credentials = credentials
        destinations = LegacyImportDestinations(
            credentials: credentials,
            pseudoLists: PseudoListStore(persistence: InMemoryPseudoListPersistence()),
            superFavorites: SuperFavoritesStore(persistence: InMemorySmallStorePersistence<SuperFavoritesDocument>()),
            layout: FavoritesLayoutStore(persistence: InMemorySmallStorePersistence<FavoritesLayoutDocument>()),
            smileyFavorites: AppSmileyFavoritesStore(persistence: InMemorySmallStorePersistence<AppSmileyFavoritesDocument>()),
            searchHistory: SmileySearchHistoryStore(persistence: InMemorySmallStorePersistence<SmileySearchHistoryDocument>()),
            uploads: RehostUploadHistoryStore(persistence: InMemorySmallStorePersistence<RehostUploadHistoryDocument>()),
            drafts: DraftStore(persistence: InMemoryDraftPersistence()),
            pending: LegacyPendingStore(persistence: InMemorySmallStorePersistence<LegacyPendingDocument>()),
            settings: InMemorySettingsStore(settings)
        )
    }

    func importer() -> LegacyImporter {
        let source = accountsFailure.map { InMemoryLegacyAccountSource(failing: $0) } ?? InMemoryLegacyAccountSource(accounts)
        let container = LegacyContainer(
            documentsDirectory: documents, cachesDirectory: caches, defaults: InMemoryLegacyDefaults(defaults), accounts: source
        )
        return LegacyImporter(container: container, destinations: destinations, state: statePersistence)
    }

    func copySample(_ sample: String, to name: String) throws {
        try LegacySamples.data(sample).write(to: documents.appending(path: name))
    }

    func write(_ text: String, to name: String) throws {
        try Data(text.utf8).write(to: documents.appending(path: name))
    }

    func remove() {
        try? FileManager.default.removeItem(at: folder)
    }

    static func cookie(_ name: String, _ value: String) -> StoredCookie {
        StoredCookie(name: name, value: value, domain: ".hardware.fr")
    }

    /// The `storage-keychain.json` synthetic accounts (LOT-004), as the Keychain archive decodes them.
    static let legacyAccounts = [
        LegacyAccountRecord(
            pseudo: "fakeuser1", displayName: "fakeuser1",
            cookies: [cookie("md_user", "fakeuser1"), cookie("md_passs", "fakepasshash1")],
            hashCheck: "0123456789abcdef0123456789abcdef01234567", avatarData: Data([0x47, 0x49, 0x46]), isMain: false
        ),
        LegacyAccountRecord(
            pseudo: "fakeuser2", displayName: "FakeUser2",
            cookies: [cookie("md_user", "fakeuser2"), cookie("md_passs", "fakepasshash2")],
            hashCheck: "fedcba9876543210fedcba9876543210fedcba98", isMain: true
        )
    ]
}

let blocklistPlist = """
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>FakeUser2</key><array>
<dict><key>alias</key><string></string><key>mode</key><integer>0</integer><key>word</key><string>fakeblocked1</string></dict>
<dict><key>alias</key><string></string><key>mode</key><integer>0</integer><key>word</key><string>\u{200B}</string></dict>
</array>
<key>ghost</key><array>
<dict><key>alias</key><string></string><key>mode</key><integer>0</integer><key>word</key><string>fakeblocked2</string></dict>
</array>
</dict></plist>
"""

let allowlistPlist = """
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><array>
<dict><key>alias</key><string></string><key>mode</key><integer>0</integer><key>word</key><string>fakeloved1</string></dict>
</array></plist>
"""

extension Harness {
    static func full() throws -> Harness {
        var harness = try Harness(settings: ["mpstorage_active": .bool(true)])
        harness.accounts = Harness.legacyAccounts
        let typical = InMemoryLegacyDefaults(plist: try LegacySamples.data("defaults-typical.plist"))
        let history = InMemoryLegacyDefaults(plist: try LegacySamples.data("defaults-search-history-typical.plist"))
        harness.defaults = [
            LegacyKeys.superFavorites: try #require(typical.value(forKey: LegacyKeys.superFavorites)),
            LegacyKeys.collapsedSections: try #require(typical.value(forKey: LegacyKeys.collapsedSections)),
            LegacyKeys.smileySearchHistory: try #require(history.value(forKey: LegacyKeys.smileySearchHistory)),
            LegacyKeys.objcDraft: .string("brouillon ObjC"),
            LegacyKeys.activeReplyDrafts: .data(
                try LegacyFormatsTests.activeDraftsJSON([ActiveDraftFixture("post-42", "réponse", 725_790_000)])
            )
        ]
        try harness.write(blocklistPlist, to: LegacyKeys.blocklistFile)
        try harness.write(allowlistPlist, to: LegacyKeys.allowlistFile)
        try harness.copySample("smiley-favorites-typical.archive", to: LegacyKeys.smileyFavoritesFile)
        try harness.copySample("upload-history-typical.json", to: LegacyKeys.uploadHistoryFile)
        let cache = harness.caches.appending(path: "cache", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try Data("<html>".utf8).write(to: cache.appending(path: "topic-1.htm"))
        return harness
    }
}

@Suite("Legacy importer (LOT-067)")
struct LegacyImporterTests {
    private let now = Date(timeIntervalSinceReferenceDate: 725_800_000)

    @Test("a first run imports every item into its store, the global items into the legacy main account")
    func fullImport() async throws {
        let harness = try Harness.full()
        defer { harness.remove() }
        let report = await harness.importer().run(now: now)

        #expect(report.isComplete)
        #expect(report.outcomes[.accounts] == .imported(2))
        #expect(report.mpStorageSwitch == .active)
        #expect(report.rejectedItems == 1)
        let book = try harness.credentials.load()
        #expect(book.accounts.map(\.pseudo) == ["fakeuser1", "fakeuser2"])
        #expect(book.main?.pseudo == "fakeuser2")
        #expect(book.accounts[0].hashCheck == Harness.legacyAccounts[0].hashCheck)
        #expect(book.accounts[0].avatarData == Data([0x47, 0x49, 0x46]))

        let lists = harness.destinations.pseudoLists
        #expect(await lists.blocklist(for: "fakeuser2").map(\.pseudo) == ["fakeblocked1"])
        #expect(await lists.blocklist(for: "ghost").map(\.pseudo) == ["fakeblocked2"])
        #expect(await lists.allowlist().map(\.pseudo) == ["fakeloved1"])

        #expect(await harness.destinations.pending.pendingSuperFavorites(for: "fakeuser2") == [12, 99, 3_050_500, 4_100_000])
        #expect(await harness.destinations.layout.collapsedSections() == ["forum-id:13", "forum-id:25", "forum-title:hardware"])
        let smileys = await harness.destinations.smileyFavorites.favorites(for: "fakeuser2")
        #expect(smileys.map(\.code) == ["[:fake1]", "[:fake2]", "[:fake3:2]"])
        #expect(await harness.destinations.smileyFavorites.favorites(for: "fakeuser1").isEmpty)
        #expect(await harness.destinations.searchHistory.top(matching: "").first?.text == "chat")
        let uploads = await harness.destinations.uploads.images()
        let legacyUploads = LegacyFormats.uploadHistory(try LegacySamples.data("upload-history-typical.json"))
        #expect(uploads.map(\.uploadedAt) == legacyUploads?.map(\.uploadedAt))
        #expect(await harness.destinations.drafts.draft(for: .legacyGlobal, account: "fakeuser2")?.text == "brouillon ObjC")
        #expect(await harness.destinations.pending.pendingReplyDrafts(for: "fakeuser2").map(\.number) == [42])
        #expect(report.outcomes[.pageCache] == .imported(1))
    }

    @Test("the legacy container is left as it was")
    func neverTouchesTheSource() async throws {
        let harness = try Harness.full()
        defer { harness.remove() }
        let names = [LegacyKeys.blocklistFile, LegacyKeys.allowlistFile, LegacyKeys.smileyFavoritesFile, LegacyKeys.uploadHistoryFile]
        let before = try names.map { try Data(contentsOf: harness.documents.appending(path: $0)) }
        _ = await harness.importer().run(now: now)
        let after = try names.map { try Data(contentsOf: harness.documents.appending(path: $0)) }
        #expect(before == after)
    }

    @Test("a second run redoes nothing: an item removed after the import does not come back")
    func idempotent() async throws {
        let harness = try Harness.full()
        defer { harness.remove() }
        _ = await harness.importer().run(now: now)
        _ = try await harness.destinations.pseudoLists.unblock("fakeblocked1", account: "fakeuser2")
        _ = try await harness.destinations.smileyFavorites.remove(code: "[:fake1]", account: "fakeuser2")

        let second = await harness.importer().run(now: now)

        #expect(LegacyImportStep.allCases.allSatisfy { second.outcomes[$0] == .alreadyDone })
        #expect(await harness.destinations.pseudoLists.blocklist(for: "fakeuser2").isEmpty)
        #expect(await harness.destinations.smileyFavorites.contains(code: "[:fake1]", account: "fakeuser2") == false)
        #expect(harness.statePersistence.document?.importVersion == 1)
    }

    @Test("a failed step runs again at the next run; the others are not redone")
    func failedStepRetried() async throws {
        var harness = try Harness.full()
        defer { harness.remove() }
        harness.accountsFailure = .sourceUnavailable
        let first = await harness.importer().run(now: now)
        #expect(first.outcomes[.accounts] == .failed(.sourceUnavailable))
        #expect(first.outcomes[.superFavorites] == .waitingForAccount)
        #expect(first.outcomes[.pseudoLists] == .waitingForAccount)
        #expect(first.outcomes[.collapsedSections] == .imported(3))
        #expect(!first.isComplete)

        harness.accountsFailure = nil
        let second = await harness.importer().run(now: now)
        #expect(second.outcomes[.accounts] == .imported(2))
        #expect(second.outcomes[.collapsedSections] == .alreadyDone)
        #expect(second.outcomes[.superFavorites] == .imported(4))
        #expect(second.outcomes[.pseudoLists] == .imported(3))
        #expect(second.isComplete)
    }

    @Test("with no legacy account, the global items wait, then go to the first account logged in, once")
    func waitsForAccount() async throws {
        var harness = try Harness.full()
        defer { harness.remove() }
        harness.accounts = []
        let first = await harness.importer().run(now: now)
        #expect(first.outcomes[.accounts] == .nothingToImport)
        #expect(first.outcomes[.smileyFavorites] == .waitingForAccount)

        let second = await harness.importer().run(currentAccount: " NewUser ", now: now)
        #expect(second.outcomes[.smileyFavorites] == .imported(3))
        #expect(await harness.destinations.smileyFavorites.favorites(for: "newuser").count == 3)
        #expect(harness.statePersistence.document?.globalAccount == "NewUser")

        let third = await harness.importer().run(currentAccount: "other", now: now)
        #expect(third.outcomes[.smileyFavorites] == .alreadyDone)
        #expect(await harness.destinations.smileyFavorites.favorites(for: "other").isEmpty)
    }

    @Test("an account SwiftHFR already stores keeps its cookies and main flag")
    func existingAccountWins() async throws {
        let fresh = Account(pseudo: "FakeUser2", cookies: [Harness.cookie("md_user", "FakeUser2"), Harness.cookie("md_passs", "newer")])
        var harness = try Harness(credentials: try InMemoryCredentialStore(accounts: [fresh]))
        defer { harness.remove() }
        harness.accounts = Harness.legacyAccounts
        let report = await harness.importer().run(now: now)
        #expect(report.outcomes[.accounts] == .imported(1))
        let book = try harness.credentials.load()
        #expect(book.main?.pseudo == "FakeUser2")
        #expect(book.account(matching: "fakeuser2")?.cookies.contains { $0.value == "newer" } == true)
    }

    @Test("legacy's main account is the last one flagged; SwiftHFR's own main account is kept")
    func mainAccountChoice() async throws {
        var harness = try Harness()
        defer { harness.remove() }
        var first = Harness.legacyAccounts[0]
        first.isMain = true
        harness.accounts = [first, Harness.legacyAccounts[1]]
        _ = await harness.importer().run(now: now)
        #expect(try harness.credentials.load().main?.pseudo == "fakeuser2")
        #expect(harness.statePersistence.document?.globalAccount == "fakeuser2")

        let own = Account(pseudo: "fakeuser1", cookies: [Harness.cookie("md_user", "fakeuser1")])
        var kept = try Harness(credentials: try InMemoryCredentialStore(accounts: [own]))
        defer { kept.remove() }
        kept.accounts = Harness.legacyAccounts
        _ = await kept.importer().run(now: now)
        #expect(try kept.credentials.load().main?.pseudo == "fakeuser1")
    }

    @Test("a blocklist keyed by a display name is filed under the account's pseudo")
    func blocklistByDisplayName() async throws {
        var harness = try Harness()
        defer { harness.remove() }
        harness.accounts = [LegacyAccountRecord(
            pseudo: "fakeuser3", displayName: "Fake Three", cookies: [Harness.cookie("md_user", "fakeuser3")], isMain: true
        )]
        let renamed = blocklistPlist.replacingOccurrences(of: "<key>FakeUser2</key>", with: "<key>Fake Three</key>")
        try harness.write(renamed, to: LegacyKeys.blocklistFile)
        _ = await harness.importer().run(now: now)
        #expect(await harness.destinations.pseudoLists.blocklist(for: "fakeuser3").map(\.pseudo) == ["fakeblocked1"])
        #expect(await harness.destinations.pseudoLists.blocklist(for: "Fake Three").isEmpty)
    }

    @Test("legacy accounts LOT-065 refuses are counted, never stored")
    func rejectedAccounts() async throws {
        var harness = try Harness()
        defer { harness.remove() }
        harness.accounts = [
            LegacyAccountRecord(pseudo: nil, displayName: "nocookie"),
            LegacyAccountRecord(pseudo: "deleted", displayName: "out", cookies: [Harness.cookie("md_user", "deleted")]),
            LegacyAccountRecord(pseudo: "alice", displayName: "alice", cookies: [Harness.cookie("md_user", "bob")], isMain: true)
        ]
        let report = await harness.importer().run(currentAccount: "carol", now: now)
        #expect(report.rejectedItems == 3)
        #expect(report.outcomes[.accounts] == .nothingToImport)
        #expect(try harness.credentials.load().accounts.isEmpty)
        #expect(harness.statePersistence.document?.globalAccount == "carol")
    }

    @Test("the v0 blocklist is read only without the dictionary file, into the main account")
    func blocklistV0() async throws {
        var harness = try Harness()
        defer { harness.remove() }
        harness.accounts = Harness.legacyAccounts
        try harness.write(allowlistPlist.replacingOccurrences(of: "fakeloved1", with: "fakeold1"), to: LegacyKeys.blocklistV0File)
        _ = await harness.importer().run(now: now)
        #expect(await harness.destinations.pseudoLists.blocklist(for: "fakeuser2").map(\.pseudo) == ["fakeold1"])
    }

    @Test("unreadable legacy data is not retried; a failing SwiftHFR store is")
    func unreadableAndDestinationFailure() async throws {
        var harness = try Harness()
        defer { harness.remove() }
        harness.accounts = Harness.legacyAccounts
        try harness.write("not a plist", to: LegacyKeys.blocklistFile)
        try harness.copySample("upload-history-corrupt-before.bin", to: LegacyKeys.uploadHistoryFile)
        try harness.copySample("smiley-favorites-typical.xml.plist", to: LegacyKeys.smileyFavoritesFile)
        harness.defaults[LegacyKeys.smileySearchHistory] = .data(try LegacySamples.data("search-history-corrupt-before.bin"))
        let report = await harness.importer().run(now: now)
        #expect(report.outcomes[.pseudoLists] == .failed(.sourceUnreadable))
        #expect(report.outcomes[.uploadHistory] == .failed(.sourceUnreadable))
        #expect(report.outcomes[.smileyFavorites] == .failed(.sourceUnreadable))
        #expect(report.outcomes[.smileySearchHistory] == .failed(.sourceUnreadable))
        #expect(report.isComplete)
    }

    @Test("a SwiftHFR store that cannot be written makes the step fail and stay pending")
    func destinationFailureRetried() async throws {
        var harness = try Harness.full()
        defer { harness.remove() }
        harness.accounts = Harness.legacyAccounts
        let broken = LegacyImportDestinations(
            credentials: harness.credentials,
            pseudoLists: harness.destinations.pseudoLists,
            superFavorites: harness.destinations.superFavorites,
            layout: FavoritesLayoutStore(persistence: InMemorySmallStorePersistence(FavoritesLayoutDocument(version: 99))),
            smileyFavorites: harness.destinations.smileyFavorites,
            searchHistory: harness.destinations.searchHistory,
            uploads: harness.destinations.uploads,
            drafts: harness.destinations.drafts,
            pending: harness.destinations.pending,
            settings: harness.destinations.settings
        )
        let container = LegacyContainer(
            documentsDirectory: harness.documents, cachesDirectory: harness.caches,
            defaults: InMemoryLegacyDefaults(harness.defaults), accounts: InMemoryLegacyAccountSource(harness.accounts)
        )
        let report = await LegacyImporter(container: container, destinations: broken, state: harness.statePersistence).run(now: now)
        #expect(report.outcomes[.collapsedSections] == .failed(.destinationFailed))
        #expect(harness.statePersistence.document?.done.contains(.collapsedSections) == false)
        #expect(!report.isComplete)
    }

    @Test("nothing in the report or its description carries a secret")
    func reportWithoutSecrets() async throws {
        let harness = try Harness.full()
        defer { harness.remove() }
        let report = await harness.importer().run(now: now)
        let text = String(describing: report) + String(reflecting: report) + String(describing: Harness.legacyAccounts)
        for secret in ["fakepasshash", "0123456789abcdef", "fedcba98", "brouillon ObjC", "fakeblocked"] {
            #expect(!text.contains(secret))
        }
    }

    @Test("an absent mpstorage_active is reported as unknown")
    func mpStorageAbsent() async throws {
        let harness = try Harness()
        defer { harness.remove() }
        let report = await harness.importer().run(currentAccount: "user", now: now)
        #expect(report.mpStorageSwitch == .notRead)
        #expect(report.outcomes[.mpStorageSwitch] == .nothingToImport)
        #expect(report.isComplete)
    }
}
