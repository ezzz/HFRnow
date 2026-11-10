import Foundation
import HFRModels
import HFRStorage
@testable import SwiftHFR
import Synchronization
import Testing

/// The per-account stores of the app, seeded with two accounts, so a test sees what an erase removes and what it keeps.
private struct SeededStores {
    let drafts = DraftStore(persistence: InMemoryDraftPersistence())
    let pseudoLists = PseudoListStore(persistence: InMemoryPseudoListPersistence())
    let positions = ReadingPositionStore(persistence: InMemoryReadingPositionPersistence())
    let superFavorites = SuperFavoritesStore(persistence: InMemorySmallStorePersistence())
    let smileyFavorites = AppSmileyFavoritesStore(persistence: InMemorySmallStorePersistence())

    static let topic = TopicID(category: .forum(13), topic: 6510)
    static let smileyURL = URL(string: "https://forum-images.hardware.fr/images/perso/fake.gif")

    var eraser: AccountDataEraser {
        AccountDataEraser(
            drafts: drafts, pseudoLists: pseudoLists, positions: positions, superFavorites: superFavorites,
            smileyFavorites: smileyFavorites
        )
    }

    /// Writes one item of every kind for each account, and one allowlist entry (shared by every account).
    func seed(_ accounts: [String]) async throws {
        let url = try #require(Self.smileyURL)
        for account in accounts {
            try await drafts.save("brouillon de \(account)", for: .reply(topic: Self.topic, page: 1), account: account)
            _ = try await pseudoLists.block("member1", account: account)
            _ = try await positions.advance(Self.topic, to: ReadingPosition(page: 2, messageNumber: 201), account: account)
            _ = try await superFavorites.add(Self.topic, account: account)
            _ = try await smileyFavorites.add(code: "[:fake]", url: url, account: account)
        }
        _ = try await pseudoLists.allow("member2")
    }

    /// How many items of each kind `account` has, in `AccountDataKind.allCases` order.
    func counts(_ account: String) async -> [Int] {
        [
            await drafts.drafts(account: account).count,
            await pseudoLists.blocklist(for: account).count,
            await positions.records(for: account).count,
            await superFavorites.favorites(for: account).count,
            await smileyFavorites.favorites(for: account).count
        ]
    }
}

/// A draft file whose next saves can be made to fail (a full disk, a locked file).
private final class FailingDraftPersistence: DraftPersistence {
    private let inner = InMemoryDraftPersistence()
    private let failures = Mutex(0)

    /// Makes the next `count` saves throw.
    func failNext(_ count: Int) {
        failures.withLock { $0 = count }
    }

    func load() throws -> DraftDocument? { try inner.load() }

    func save(_ document: DraftDocument) throws {
        let fails = failures.withLock { count in
            defer { count = max(0, count - 1) }
            return count > 0
        }
        if fails { throw CocoaError(.fileWriteOutOfSpace) }
        try inner.save(document)
    }

    func quarantineUnreadableData() throws { try inner.quarantineUnreadableData() }
}

/// A credential store whose item cannot be deleted `failures` times (the Keychain refusing a delete).
private final class UndeletableCredentialStore: CredentialStore {
    let inner: InMemoryCredentialStore
    private let failures: Mutex<Int>

    init(accounts: [Account], failures: Int) throws {
        inner = try InMemoryCredentialStore(accounts: accounts)
        self.failures = Mutex(failures)
    }

    func load() throws -> AccountBook { try inner.load() }

    func update<Value>(_ body: (inout AccountBook) throws -> Value) throws -> Value { try inner.update(body) }

    func removeAll() throws {
        let fails = failures.withLock { count in
            defer { count = max(0, count - 1) }
            return count > 0
        }
        if fails { throw CredentialStoreError.keychain(status: -25_308) }
        try inner.removeAll()
    }
}

struct AccountDataEraserTests {
    @Test func erasesEveryStoreOfTheAccountAndNothingOfTheOthers() async throws {
        let stores = SeededStores()
        try await stores.seed(["user1", "user2"])
        #expect(await stores.counts("user1") == [1, 1, 1, 1, 1])

        let failed = await stores.eraser.erase(account: "user1")

        #expect(failed.isEmpty)
        #expect(await stores.counts("user1") == [0, 0, 0, 0, 0])
        #expect(await stores.counts("user2") == [1, 1, 1, 1, 1])
        // The allowlist belongs to no account: it stays.
        #expect(await stores.pseudoLists.allowlist().map(\.pseudo) == ["member2"])
        // The account's keys leave the documents, not only their items.
        #expect(await stores.superFavorites.accountKeys() == ["user2"])
        #expect(await stores.smileyFavorites.accountKeys() == ["user2"])
        #expect(await stores.positions.accounts() == ["user2"])
    }

    @Test func triesEveryStoreAndReportsTheOnesThatFailed() async throws {
        let stores = SeededStores()
        try await stores.seed(["user1"])
        let persistence = FailingDraftPersistence()
        let drafts = DraftStore(persistence: persistence)
        try await drafts.save("brouillon", for: .reply(topic: SeededStores.topic, page: 1), account: "user1")
        let eraser = AccountDataEraser(
            drafts: drafts, pseudoLists: stores.pseudoLists, positions: stores.positions,
            superFavorites: stores.superFavorites, smileyFavorites: stores.smileyFavorites
        )
        persistence.failNext(1)

        let failed = await eraser.erase(account: "user1")

        #expect(failed == [.drafts])
        #expect(await drafts.drafts(account: "user1").count == 1)
        // The stores after the failed one were erased all the same.
        #expect(await stores.counts("user1").dropFirst().allSatisfy { $0 == 0 })
        // Erasing only what failed, once the file can be written again.
        #expect(await eraser.erase(account: "user1", kinds: failed).isEmpty)
        #expect(await drafts.drafts(account: "user1").isEmpty)
    }

    @Test func theLiveEraserWritesTheStoresTheScreensUse() {
        let live = AccountDataEraser.live
        #expect(live.drafts === ComposerServices.liveDrafts)
        #expect(live.pseudoLists === PseudoListsSnapshot.liveStore)
        #expect(live.positions === LiveReaderPositionRecorder.store)
        #expect(live.superFavorites === FavoritesStores.shared.superFavorites)
        #expect(live.smileyFavorites === ComposerServices.liveSmileyFavorites)
    }

    @Test func everyKindHasAFrenchName() {
        #expect(AccountDataKind.allCases.map(\.title) == [
            "les brouillons", "la liste noire", "les positions de lecture", "les super-favoris", "les smileys favoris"
        ])
    }
}

@MainActor
struct AccountDeletionModelTests {
    @Test func procedureIsHFRsPersonalDataPageOverHTTPS() throws {
        // HFR-PROTOCOL §6b "Account deletion" (`R98a`, footer of `R01`): no deletion page of its own, no address in the app.
        let url = try #require(AccountDeletionModel.procedureURL)
        #expect(url.absoluteString == "https://www.hardware.fr/html/donnees_personnelles/")
    }

    @Test func erasingTheOnlyAccountLeavesNoKeychainItemNoSessionAndNoData() async throws {
        let store = try InMemoryCredentialStore(accounts: [Fake.account("user1", main: true)])
        let accounts = makeModel(store: store)
        await accounts.restore()
        let stores = SeededStores()
        try await stores.seed(["user1"])
        let deletion = AccountDeletionModel(accounts: accounts, eraser: stores.eraser)
        let row = try #require(accounts.rows.first)

        await deletion.erase(row)

        #expect(deletion.phase == .erased(name: row.displayName))
        #expect(store.envelope == nil)
        #expect(accounts.rows.isEmpty)
        #expect(accounts.currentSession == nil)
        #expect(accounts.session(for: "user1") == nil)
        #expect(await stores.counts("user1") == [0, 0, 0, 0, 0])
        #expect(!deletion.canRetry)
    }

    @Test func erasingOneAccountKeepsTheOtherWithItsSessionAndData() async throws {
        let store = try InMemoryCredentialStore(accounts: [Fake.account("user1", main: true), Fake.account("user2")])
        let accounts = makeModel(store: store)
        await accounts.restore()
        let other = try #require(accounts.session(for: "user2"))
        let stores = SeededStores()
        try await stores.seed(["user1", "user2"])
        let deletion = AccountDeletionModel(accounts: accounts, eraser: stores.eraser)
        let row = try #require(accounts.rows.first { $0.id == "user1" })

        await deletion.erase(row)

        #expect(try store.accounts().map(\.pseudo) == ["user2"])
        #expect(accounts.current?.id == "user2")
        #expect(accounts.currentSession === other)
        #expect(await stores.counts("user1") == [0, 0, 0, 0, 0])
        #expect(await stores.counts("user2") == [1, 1, 1, 1, 1])
    }

    @Test func aRefusedRemovalErasesNothing() async throws {
        let store = try InMemoryCredentialStore(accounts: [Fake.account("user1", main: true)])
        let accounts = makeModel(store: store)
        await accounts.restore()
        let stores = SeededStores()
        try await stores.seed(["user1"])
        let deletion = AccountDeletionModel(accounts: accounts, eraser: stores.eraser)
        let row = try #require(accounts.rows.first)
        // The item became unreadable after launch: the store refuses to rewrite it.
        store.envelope = Data("not an envelope".utf8)

        let message = AccountMessages.message(for: CredentialStoreError.corrupted)

        await deletion.erase(row)

        #expect(deletion.phase == .refused(message: message))
        #expect(await stores.counts("user1") == [1, 1, 1, 1, 1])
        #expect(!deletion.canRetry)
    }

    @Test func anAccountRemovedMeanwhileIsReportedAndNothingIsErased() async throws {
        let store = try InMemoryCredentialStore(accounts: [Fake.account("user1", main: true)])
        let accounts = makeModel(store: store)
        await accounts.restore()
        let stores = SeededStores()
        try await stores.seed(["user1"])
        let deletion = AccountDeletionModel(accounts: accounts, eraser: stores.eraser)
        let row = try #require(accounts.rows.first)
        try accounts.remove(row.id)
        let message = try #require(AccountMessages.message(for: .unknownAccount))

        await deletion.erase(row)

        #expect(deletion.phase == .refused(message: message))
        #expect(await stores.counts("user1") == [1, 1, 1, 1, 1])
    }

    @Test func aStoreThatFailedIsNamedAndErasedByRetry() async throws {
        let store = try InMemoryCredentialStore(accounts: [Fake.account("user1", main: true)])
        let accounts = makeModel(store: store)
        await accounts.restore()
        let stores = SeededStores()
        try await stores.seed(["user1"])
        let persistence = FailingDraftPersistence()
        let drafts = DraftStore(persistence: persistence)
        try await drafts.save("brouillon", for: .reply(topic: SeededStores.topic, page: 1), account: "user1")
        let eraser = AccountDataEraser(
            drafts: drafts, pseudoLists: stores.pseudoLists, positions: stores.positions,
            superFavorites: stores.superFavorites, smileyFavorites: stores.smileyFavorites
        )
        let deletion = AccountDeletionModel(accounts: accounts, eraser: eraser)
        let row = try #require(accounts.rows.first)
        persistence.failNext(1)

        await deletion.erase(row)

        #expect(deletion.phase == .partial(name: row.displayName, failures: ["les brouillons"]))
        #expect(deletion.canRetry)
        #expect(store.envelope == nil)
        #expect(await drafts.drafts(account: "user1").count == 1)

        await deletion.retry()

        #expect(deletion.phase == .erased(name: row.displayName))
        #expect(await drafts.drafts(account: "user1").isEmpty)
        #expect(!deletion.canRetry)
    }

    @Test func aKeychainItemThatCannotBeDeletedIsNamedAndDeletedByRetry() async throws {
        let store = try UndeletableCredentialStore(accounts: [Fake.account("user1", main: true)], failures: 1)
        let accounts = makeModel(store: store)
        await accounts.restore()
        let stores = SeededStores()
        try await stores.seed(["user1"])
        let deletion = AccountDeletionModel(accounts: accounts, eraser: stores.eraser)
        let row = try #require(accounts.rows.first)

        await deletion.erase(row)

        #expect(deletion.phase == .partial(name: row.displayName, failures: ["l’élément du trousseau"]))
        // The account itself is gone and its data erased; only the empty item is left.
        #expect(accounts.rows.isEmpty)
        #expect(store.inner.envelope != nil)
        #expect(await stores.counts("user1") == [0, 0, 0, 0, 0])

        await deletion.retry()

        #expect(deletion.phase == .erased(name: row.displayName))
        #expect(store.inner.envelope == nil)
    }

    @Test func theKeychainItemStaysWhileAnotherAccountIsStored() throws {
        let store = try InMemoryCredentialStore(accounts: [Fake.account("user1", main: true)])
        let accounts = makeModel(store: store)

        try accounts.removeStoreItemIfEmpty()

        #expect(try store.accounts().map(\.pseudo) == ["user1"])
    }
}
