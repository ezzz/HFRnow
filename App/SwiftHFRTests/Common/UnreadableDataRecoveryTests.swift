import Foundation
import HFRClient
import HFRModels
import HFRStorage
@testable import SwiftHFR
import Testing

/// #1182: every screen that shows a local store it cannot read offers « Repartir de zéro »; once the member confirmed, the
/// unreadable data is set aside (`.corrupt`, never deleted) and the store is writable again. The favourites options, the
/// smiley picker and the composer's drafts notice are tested in their own suites.
@MainActor
struct UnreadableDataRecoveryTests {
    /// A directory removed by the caller.
    private func directory() throws -> URL {
        let directory = URL.temporaryDirectory.appending(path: "UnreadableDataRecovery-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// "Réessayer" reads the same bytes again; "Repartir de zéro" sets them aside as `.corrupt` and the editor can write again.
    @Test func discardAfterConfirmationMakesTheStoreWritable() async throws {
        let directory = try directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "lists.json")
        let garbage = Data("not json".utf8)
        try garbage.write(to: file)
        let persistence = FilePseudoListPersistence(fileURL: file)
        let model = PseudoListEditorModel(
            kind: .allowlist, manager: PseudoListManager(store: PseudoListStore(persistence: persistence), account: "moi")
        )
        await model.load()
        #expect(model.unreadableMessage != nil)
        await model.retry()
        #expect(model.unreadableMessage != nil)
        await model.discardUnreadable()
        #expect(model.unreadableMessage == nil && model.errorMessage == nil)
        model.draft = "Ami"
        await model.add()
        #expect(model.pseudos == ["Ami"])
        #expect(try Data(contentsOf: persistence.quarantineURL) == garbage)
    }

    /// The upload history from a newer build: the panel offers the way out, and the history is writable afterwards.
    @Test func anUnreadableUploadHistoryCanBeDiscarded() async throws {
        let store = RehostUploadHistoryStore(
            persistence: InMemorySmallStorePersistence(
                RehostUploadHistoryDocument(version: RehostUploadHistoryDocument.currentVersion + 1)
            )
        )
        let services = ImageUploadServices(
            uploader: nil, hostName: "img.example", preparer: ImageIOPreparer(), history: LiveImageUploadHistory(store: store),
            settings: InMemorySettingsStore()
        )
        let model = ImageUploadModel(services: services)
        await model.load()
        #expect(model.historyIsUnreadable && model.historyWarning != nil)
        await model.discardUnreadableHistory()
        #expect(!model.historyIsUnreadable && model.historyWarning == nil)
        #expect(await store.loadFailure() == nil)
    }

    /// MP storage copies from a newer build: Réglages offers the way out; once confirmed the model shows an empty copy.
    @Test func anUnreadableMPStorageCopyCanBeDiscarded() async {
        let copies = MPStorageCopyStore(
            persistence: InMemorySmallStorePersistence(MPStorageCopyDocument(version: MPStorageCopyDocument.currentVersion + 1))
        )
        let model = mpStorageModel(copies: copies, discard: { try await copies.discardUnreadableData() })
        await model.start()
        #expect(model.copyIsUnreadable)
        #expect(model.status == .failed("La copie locale du stockage MP est illisible."))
        await model.discardUnreadableCopy()
        #expect(!model.copyIsUnreadable && model.status == .idle)
        #expect(await copies.loadFailure() == nil)
    }

    /// Without a way out (tests, previews), nothing is offered.
    @Test func withoutADiscardNothingIsOffered() async {
        let copies = MPStorageCopyStore(
            persistence: InMemorySmallStorePersistence(MPStorageCopyDocument(version: MPStorageCopyDocument.currentVersion + 1))
        )
        let model = mpStorageModel(copies: copies, discard: nil)
        await model.start()
        #expect(!model.copyIsUnreadable)
    }

    /// Reading positions the wipe could not read: the account screen offers the way out, and the positions are then empty.
    @Test func unreadablePositionsMetByAWipeCanBeDiscarded() async throws {
        let store = try InMemoryCredentialStore(accounts: [Fake.account("user1", main: true)])
        let accounts = makeModel(store: store)
        await accounts.restore()
        let stores = SeededStores()
        let positions = ReadingPositionStore(persistence: UnreadablePositionPersistence())
        let deletion = AccountDeletionModel(accounts: accounts, eraser: stores.eraser(positions: positions))
        let row = try #require(accounts.rows.first)
        await deletion.erase(row)
        #expect(deletion.positionsAreUnreadable)
        await deletion.discardUnreadablePositions()
        #expect(!deletion.positionsAreUnreadable)
        // Positions were the wipe's only failure: once they are set aside, the account reads as erased.
        #expect(deletion.phase == .erased(name: row.displayName))
        #expect(await positions.loadFailure() == nil)
    }

    private func mpStorageModel(
        copies: MPStorageCopyStore, discard: (@Sendable () async throws -> Void)?
    ) -> MPStorageSyncModel {
        let account = "Alice"
        return MPStorageSyncModel(
            account: account,
            sync: MPStorageSync(
                remote: FakeMPStorageRemote(thread: nil),
                persistence: MPStorageCopyPersistence(store: copies, account: account)
            ),
            states: MPStorageSyncStateStore(settings: InMemorySettingsStore()), isLoggedIn: { false },
            discardCopies: discard
        )
    }
}
