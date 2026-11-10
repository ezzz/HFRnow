import Foundation
import HFRModels
import HFRStorage
@testable import SwiftHFR
import Testing

struct AccountDataEraserTests {
    @Test func erasesEveryStoreOfTheAccountAndNothingOfTheOthers() async throws {
        let stores = SeededStores()
        try await stores.seed(["user1", "user2"])
        #expect(await stores.counts("user1") == [1, 1, 1, 1, 1, 1])

        let failed = await stores.eraser.erase(account: "user1")

        #expect(failed.isEmpty)
        #expect(await stores.counts("user1") == [0, 0, 0, 0, 0, 0])
        #expect(await stores.counts("user2") == [1, 1, 1, 1, 1, 1])
        // The allowlist belongs to no account: it stays.
        #expect(await stores.pseudoLists.allowlist().map(\.pseudo) == ["member2"])
        // The account's keys leave the documents, not only their items.
        #expect(await stores.superFavorites.accountKeys() == ["user2"])
        #expect(await stores.smileyFavorites.accountKeys() == ["user2"])
        #expect(await stores.positions.accounts() == ["user2"])
        #expect(await stores.legacyPending.accountKeys() == ["user2"])
    }

    @Test func triesEveryStoreAndReportsTheOnesThatFailed() async throws {
        let stores = SeededStores()
        try await stores.seed(["user1"])
        let persistence = FailingDraftPersistence()
        let drafts = DraftStore(persistence: persistence)
        try await drafts.save("brouillon", for: .reply(topic: SeededStores.topic, page: 1), account: "user1")
        let eraser = stores.eraser(drafts: drafts)
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

    @Test func positionsStoredUnderAnotherSpellingAreErasedAndKeysAreListed() async throws {
        let stores = SeededStores()
        try await stores.seed(["user2"])
        _ = try await stores.positions.advance(SeededStores.topic, to: ReadingPosition(page: 1), account: "User1")
        #expect(await stores.eraser.accountKeys() == ["user1", "user2"])

        #expect(await stores.eraser.erase(account: "user1").isEmpty)

        #expect(await stores.positions.accounts() == ["user2"])
        #expect(await stores.eraser.accountKeys() == ["user2"])
    }

    @Test func anUnreadablePositionStoreIsReportedNotErasedInSilence() async {
        let stores = SeededStores()
        let eraser = stores.eraser(positions: ReadingPositionStore(persistence: UnreadablePositionPersistence()))

        #expect(await eraser.erase(account: "user1") == [.readingPositions])
    }

    @Test func theLiveEraserWritesTheStoresTheScreensUse() {
        let live = AccountDataEraser.live
        #expect(live.drafts === ComposerServices.liveDrafts)
        #expect(live.pseudoLists === PseudoListsSnapshot.liveStore)
        #expect(live.positions === LiveReaderPositionRecorder.store)
        #expect(live.superFavorites === FavoritesStores.shared.superFavorites)
        #expect(live.smileyFavorites === ComposerServices.liveSmileyFavorites)
        #expect(live.legacyPending === LegacyImportServices.livePending)
        #expect(live.legacyImport === LegacyImportServices.liveImporter)
    }

    @Test func everyKindHasAFrenchName() {
        #expect(AccountDataKind.allCases.map(\.title) == [
            "les brouillons", "la liste noire", "les positions de lecture", "les super-favoris", "les smileys favoris",
            "les éléments en attente de l’ancienne app"
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
        #expect(await stores.counts("user1") == [0, 0, 0, 0, 0, 0])
        // The legacy import will not bring the account back: legacy's own Keychain item still lists it.
        #expect(try stores.erasedAccounts.keys() == ["user1"])
        #expect(deletion.leftovers.isEmpty)
        #expect(!deletion.keychainItemPending)
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
        #expect(await stores.counts("user1") == [0, 0, 0, 0, 0, 0])
        #expect(await stores.counts("user2") == [1, 1, 1, 1, 1, 1])
    }

    @Test func theAccountIsExcludedFromTheLegacyImportBeforeItIsRemoved() async throws {
        let inner = try InMemoryCredentialStore(accounts: [Fake.account("user1", main: true), Fake.account("user2")])
        let stores = SeededStores()
        let store = ErasedAtWriteCredentialStore(inner, erased: stores.erasedAccounts)
        let accounts = makeModel(store: store)
        await accounts.restore()
        try await stores.seed(["user1", "user2"])
        // Legacy's Keychain item still lists user1, and the import has not completed.
        let importer = stores.legacyImporter(credentials: store, legacyAccounts: [LegacyAccountRecord(
            pseudo: "user1", displayName: "user1", isMain: true
        )])
        let deletion = AccountDeletionModel(accounts: accounts, eraser: stores.eraser(importer: importer))
        let row = try #require(accounts.rows.first { $0.id == "user1" })
        let writesBefore = store.erasedAtWrites.count

        await deletion.erase(row)
        // The run the app starts when the current account changes (LOT-158), queued after the removal.
        _ = await importer.run(currentAccount: accounts.current?.id)

        #expect(deletion.phase == .erased(name: row.displayName))
        // The removal, the wipe's first write to the account store, already saw user1 recorded.
        #expect(store.erasedAtWrites.dropFirst(writesBefore).first == ["user1"])
        #expect(try inner.accounts().map(\.pseudo) == ["user2"])
    }

    @Test func anUnwritableLegacyImportListErasesNothing() async throws {
        let store = try InMemoryCredentialStore(accounts: [Fake.account("user1", main: true)])
        let accounts = makeModel(store: store)
        await accounts.restore()
        let stores = SeededStores()
        try await stores.seed(["user1"])
        let importer = stores.legacyImporter(erased: UnwritableErasedAccountStore())
        let deletion = AccountDeletionModel(accounts: accounts, eraser: stores.eraser(importer: importer))
        let row = try #require(accounts.rows.first)

        await deletion.erase(row)

        #expect(deletion.phase == .refused(message: AccountDeletionModel.legacyImportFailure))
        #expect(try store.accounts().map(\.pseudo) == ["user1"])
        #expect(await stores.counts("user1") == [1, 1, 1, 1, 1, 1])
        #expect(!deletion.isErasing)
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
        #expect(await stores.counts("user1") == [1, 1, 1, 1, 1, 1])
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
        #expect(await stores.counts("user1") == [1, 1, 1, 1, 1, 1])
    }

    @Test func aStoreThatFailedIsNamedAndOfferedAgainAsALeftover() async throws {
        let store = try InMemoryCredentialStore(accounts: [Fake.account("user1", main: true)])
        let accounts = makeModel(store: store)
        await accounts.restore()
        let stores = SeededStores()
        try await stores.seed(["user1"])
        let persistence = FailingDraftPersistence()
        let drafts = DraftStore(persistence: persistence)
        try await drafts.save("brouillon", for: .reply(topic: SeededStores.topic, page: 1), account: "user1")
        let eraser = stores.eraser(drafts: drafts)
        let deletion = AccountDeletionModel(accounts: accounts, eraser: eraser)
        let row = try #require(accounts.rows.first)
        persistence.failNext(1)

        await deletion.erase(row)

        #expect(deletion.phase == .partial(name: row.displayName, failures: ["les brouillons"]))
        #expect(store.envelope == nil)
        #expect(await drafts.drafts(account: "user1").count == 1)
        // What is left is read back from the stores, so it is still offered after a relaunch.
        #expect(deletion.leftovers == ["user1"])
        let relaunched = AccountDeletionModel(accounts: accounts, eraser: eraser)
        await relaunched.refreshLeftovers()
        #expect(relaunched.leftovers == ["user1"])

        await relaunched.eraseLeftover("user1")

        #expect(relaunched.phase == .erased(name: "user1"))
        #expect(await drafts.drafts(account: "user1").isEmpty)
        #expect(relaunched.leftovers.isEmpty)
    }

    @Test func dataOfAnAccountRemovedWithoutAWipeIsOfferedAndErased() async throws {
        let store = try InMemoryCredentialStore(accounts: [Fake.account("user1", main: true), Fake.account("user2")])
        let accounts = makeModel(store: store)
        await accounts.restore()
        let stores = SeededStores()
        try await stores.seed(["user1", "user2"])
        let deletion = AccountDeletionModel(accounts: accounts, eraser: stores.eraser)
        await deletion.refreshLeftovers()
        #expect(deletion.leftovers.isEmpty)
        // "Retirer" on the accounts screen keeps the data (legacy `MultisManager.m:125-153`).
        try accounts.remove("user1")

        await deletion.refreshLeftovers()
        #expect(deletion.leftovers == ["user1"])
        await deletion.eraseLeftover("user1")

        #expect(await stores.counts("user1") == [0, 0, 0, 0, 0, 0])
        #expect(await stores.counts("user2") == [1, 1, 1, 1, 1, 1])
        #expect(deletion.leftovers.isEmpty)
        #expect(try store.accounts().map(\.pseudo) == ["user2"])
    }

    @Test func aStoredAccountIsNeverErasedAsALeftover() async throws {
        let store = try InMemoryCredentialStore(accounts: [Fake.account("User1", main: true)])
        let accounts = makeModel(store: store)
        await accounts.restore()
        let stores = SeededStores()
        try await stores.seed(["User1"])
        let deletion = AccountDeletionModel(accounts: accounts, eraser: stores.eraser)

        // A key that was left over, then logged in again before the tap.
        await deletion.eraseLeftover("user1")

        #expect(deletion.phase == .idle)
        #expect(await stores.counts("User1") == [1, 1, 1, 1, 1, 1])
    }

    @Test func noLeftoverIsOfferedWhileTheAccountStoreCannotBeRead() async throws {
        let store = InMemoryCredentialStore(envelope: Data("not an envelope".utf8))
        let accounts = makeModel(store: store)
        await accounts.restore()
        #expect(accounts.storeProblem == .corrupted)
        let stores = SeededStores()
        try await stores.seed(["user1"])
        let deletion = AccountDeletionModel(accounts: accounts, eraser: stores.eraser)

        await deletion.refreshLeftovers()

        #expect(deletion.leftovers.isEmpty)
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
        #expect(deletion.keychainItemPending)
        // The account itself is gone and its data erased; only the empty item is left.
        #expect(accounts.rows.isEmpty)
        #expect(store.inner.envelope != nil)
        #expect(await stores.counts("user1") == [0, 0, 0, 0, 0, 0])

        await deletion.retry()

        #expect(deletion.phase == .idle)
        #expect(!deletion.keychainItemPending)
        #expect(store.inner.envelope == nil)
    }

    @Test func aKeychainItemStillRefusedOnRetryIsReportedAndOpeningTheScreenDeletesItLater() async throws {
        let store = try UndeletableCredentialStore(accounts: [Fake.account("user1", main: true)], failures: 2)
        let accounts = makeModel(store: store)
        await accounts.restore()
        let deletion = AccountDeletionModel(accounts: accounts, eraser: SeededStores().eraser)
        let row = try #require(accounts.rows.first)
        await deletion.erase(row)

        await deletion.retry()

        #expect(deletion.phase == .refused(message: "L’élément vide du trousseau n’a pas pu être supprimé. Réessayez."))
        #expect(deletion.keychainItemPending)
        // As after a relaunch: a new model, the screen opens and reads the stores.
        let relaunched = AccountDeletionModel(accounts: accounts, eraser: SeededStores().eraser)
        await relaunched.refreshLeftovers()
        #expect(store.inner.envelope == nil)
        #expect(!relaunched.keychainItemPending)
    }

    @Test func openingTheScreenDeletesTheEmptyItemLeftByRemovingTheLastAccount() async throws {
        let store = try InMemoryCredentialStore(accounts: [Fake.account("user1", main: true)])
        let accounts = makeModel(store: store)
        await accounts.restore()
        try accounts.remove("user1")
        #expect(store.envelope != nil)
        let deletion = AccountDeletionModel(accounts: accounts, eraser: SeededStores().eraser)

        await deletion.refreshLeftovers()

        #expect(store.envelope == nil)
    }

    @Test func theKeychainItemStaysWhileAnotherAccountIsStored() throws {
        let store = try InMemoryCredentialStore(accounts: [Fake.account("user1", main: true)])
        let accounts = makeModel(store: store)

        try accounts.removeStoreItemIfEmpty()

        #expect(try store.accounts().map(\.pseudo) == ["user1"])
    }
}
