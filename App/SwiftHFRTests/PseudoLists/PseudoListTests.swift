import Dispatch
import Foundation
import HFRModels
import HFRStorage
@testable import SwiftHFR
import Synchronization
import Testing

/// A persistence that cannot be read: counts the saves, so a test can prove nothing was written.
private final class UnreadablePersistence: PseudoListPersistence {
    private let saves = Mutex(0)
    var saveCount: Int { saves.withLock { $0 } }
    func load() throws -> PseudoListDocument? { throw CocoaError(.fileReadCorruptFile) }
    func save(_ document: PseudoListDocument) throws { saves.withLock { $0 += 1 } }
    func quarantineUnreadableData() throws {}
}

/// A persistence whose saves wait while the gate is closed, so a test can hold a write and look at the editor meanwhile.
private final class GatedPersistence: PseudoListPersistence {
    private let inner = InMemoryPseudoListPersistence()
    private let closed = Mutex(false)
    private let gate = DispatchSemaphore(value: 0)
    func close() { closed.withLock { $0 = true } }
    func open() { if closed.withLock({ let was = $0; $0 = false; return was }) { gate.signal() } }
    func load() throws -> PseudoListDocument? { try inner.load() }
    func save(_ document: PseudoListDocument) throws {
        if closed.withLock({ $0 }) { gate.wait() }
        try inner.save(document)
    }
    func quarantineUnreadableData() throws { try inner.quarantineUnreadableData() }
}

private struct Fixture {
    let manager: PseudoListManager
    let store: PseudoListStore
    let snapshot: PseudoListsSnapshot
}

private func fixture(account: String? = "moi", blocklist: [String] = [], allowlist: [String] = []) async throws -> Fixture {
    let store = PseudoListStore(persistence: InMemoryPseudoListPersistence())
    for pseudo in blocklist { try await store.block(pseudo, account: "moi") }
    for pseudo in allowlist { try await store.allow(pseudo) }
    let lists = PseudoListsSnapshot(store: store, account: account)
    return Fixture(manager: PseudoListManager(store: store, account: account, snapshot: lists), store: store, snapshot: lists)
}

/// LOT-118: the lists are edited through `PseudoListStore`, by the editors, the message menu and the profile.
@MainActor
struct PseudoListManagerTests {
    @Test func theToggleAddsThenRemovesAndSaysSoInLegacyWords() async throws {
        let setup = try await fixture()
        let lists = setup.manager
        let store = setup.store
        let added = try #require(await lists.toggle("Troll", in: .blocklist))
        #expect(added.message == "BIM! Troll ajouté à la liste noire" && added.changed)
        #expect(await store.isBlocked("troll", account: "moi"))
        let removed = try #require(await lists.toggle("TROLL", in: .blocklist))
        #expect(removed.message == "TROLL a été supprimé de la liste noire" && removed.changed)
        #expect(await store.blocklist(for: "moi").isEmpty)
    }

    @Test func theAllowlistToggleUsesTheLoveListSentences() async throws {
        let setup = try await fixture()
        let lists = setup.manager
        let store = setup.store
        #expect(await lists.toggle("Ami", in: .allowlist)?.message == "BOUM BOUM ! Ami ajouté à la love list \u{2665}")
        #expect(await store.allowlist().map(\.pseudo) == ["Ami"])
        #expect(await lists.toggle("ami", in: .allowlist)?.message == "OH NOES ! ami a été supprimé de la love list")
        #expect(await store.allowlist().isEmpty)
    }

    /// A blocked pseudo is never "allowed" for the reader, but the allowlist toggle still removes the entry it holds.
    @Test func theAllowlistToggleReadsTheAllowlistNotTheBlockedRule() async throws {
        let setup = try await fixture(blocklist: ["Ami"], allowlist: ["Ami"])
        let lists = setup.manager
        let store = setup.store
        #expect(await lists.toggle("Ami", in: .allowlist)?.message == "OH NOES ! Ami a été supprimé de la love list")
        #expect(await store.allowlist().isEmpty)
    }

    @Test func aPseudoIsCleanedLikeTheStoreDoesBeforeItIsKeptAndShown() async throws {
        let setup = try await fixture()
        let lists = setup.manager
        let store = setup.store
        let result = try #require(await lists.toggle("  Pseu\u{200B}do  ", in: .blocklist))
        #expect(result.message == "BIM! Pseudo ajouté à la liste noire")
        #expect(await store.blocklist(for: "moi").map(\.pseudo) == ["Pseudo"])
    }

    @Test func anEmptyPseudoDoesNothing() async throws {
        let setup = try await fixture()
        let lists = setup.manager
        let store = setup.store
        #expect(await lists.toggle(" \u{200B} ", in: .blocklist) == nil)
        #expect(await store.blocklist(for: "moi").isEmpty)
    }

    // LOT-159 (Fable r1290 #1): the key is the URL-encoded `md_user` (`AccountsModelLoginTests`: `user%20two` for "user two"),
    // the page prints the pseudo; compared raw and decoded, as `AccountBook.checkSessionCookie`.
    @Test func theOwnPseudoIsFoundFromAURLEncodedAccountKey() async throws {
        let lists = try await fixture(account: "user%20two").manager
        #expect(lists.isOwn("user two") && lists.isOwn("User Two") && lists.isOwn("user%20two"))
        #expect(!lists.isOwn("user three"))
        #expect(try await fixture(account: "user+two").manager.isOwn("user two"))
        // Not a UTF-8 percent-encoding (how HFR encodes accents is not captured): compared raw only, never a crash.
        #expect(try await fixture(account: "caf%E9").manager.isOwn("caf%E9"))
        #expect(PseudoListManager.keyForms(of: "caf%E9") == ["caf%E9"])
    }

    @Test func theBlocklistBelongsToAnAccountAndTheAllowlistDoesNot() async throws {
        let setup = try await fixture(account: nil)
        let lists = setup.manager
        let store = setup.store
        #expect(!lists.isAvailable(.blocklist) && lists.isAvailable(.allowlist))
        #expect(await lists.pseudos(of: .blocklist).isEmpty)
        #expect(await lists.toggle("Troll", in: .blocklist)?.changed == false)
        #expect(await lists.toggle("Ami", in: .allowlist)?.changed == true)
        #expect(await store.allowlist().count == 1)
    }

    @Test func theListsAreShownSortedWithoutRegardToCase() async throws {
        let setup = try await fixture(blocklist: ["zorro", "Alice", "bob"])
        let lists = setup.manager
        #expect(await lists.pseudos(of: .blocklist) == ["Alice", "bob", "zorro"])
    }

    @Test func aWriteRefreshesTheReadersSnapshotSoThePageIsBuiltWithIt() async throws {
        let setup = try await fixture(blocklist: ["Troll"])
        let lists = setup.manager
        let snapshot = setup.snapshot
        await snapshot.refresh()
        #expect(snapshot.current.blocklist == ["Troll"])
        try await lists.add("Autre", to: .blocklist)
        #expect(snapshot.current.blocklist.sorted() == ["Autre", "Troll"])
        try await lists.remove("Troll", from: .blocklist)
        try await lists.remove("Autre", from: .blocklist) // the last entry
        #expect(snapshot.current.blocklist.isEmpty)
    }

    /// An unreadable file refuses every write: nothing is saved, the stored data is never replaced by an empty list.
    @Test func anUnreadableFileIsNeverOverwrittenByAToggleOrARemoval() async throws {
        let persistence = UnreadablePersistence()
        let store = PseudoListStore(persistence: persistence)
        let lists = PseudoListManager(store: store, account: "moi")
        #expect(await lists.toggle("Troll", in: .blocklist)?.changed == false)
        #expect(await lists.toggle("Ami", in: .allowlist)?.message == "Whitelist impossible")
        await #expect(throws: PseudoListError.self) { try await lists.remove("Troll", from: .blocklist) }
        #expect(persistence.saveCount == 0)
    }
}

/// A persistence that reads fine and refuses every write.
private final class FailingSavePersistence: PseudoListPersistence {
    func load() throws -> PseudoListDocument? { nil }
    func save(_ document: PseudoListDocument) throws { throw CocoaError(.fileWriteUnknown) }
    func quarantineUnreadableData() throws {}
}

/// The two editors of Réglages.
@MainActor @Suite(.timeLimit(.minutes(5)))
struct PseudoListEditorModelTests {
    /// #1175: the alert's title says what failed, never « Erreur ».
    @Test func aRefusedAddSaysAddFailedInTheTitle() async {
        let store = PseudoListStore(persistence: FailingSavePersistence())
        let model = PseudoListEditorModel(kind: .blocklist, manager: PseudoListManager(store: store, account: "moi"))
        await model.load()
        model.draft = "Troll"
        await model.add()
        #expect(model.errorMessage == PseudoListKind.blocklist.addFailure)
        #expect(model.errorTitle == "Ajout impossible")
    }

    @Test func theFieldIsCleanedAndAddedThenEmptied() async throws {
        let setup = try await fixture()
        let lists = setup.manager
        let store = setup.store
        let model = PseudoListEditorModel(kind: .allowlist, manager: lists)
        await model.load()
        #expect(model.pseudos.isEmpty && model.hasLoaded && !model.canAdd)
        model.draft = "  Ami\u{200B} "
        #expect(model.canAdd)
        await model.add()
        #expect(model.pseudos == ["Ami"] && model.draft.isEmpty && model.errorMessage == nil)
        #expect(await store.allowlist().map(\.pseudo) == ["Ami"])
    }

    @Test func aPseudoAlreadyListedInAnotherCaseSaysSoAndIsNotDuplicated() async throws {
        let setup = try await fixture(blocklist: ["Troll"])
        let lists = setup.manager
        let store = setup.store
        let model = PseudoListEditorModel(kind: .blocklist, manager: lists)
        await model.load()
        model.draft = "troll"
        await model.add()
        #expect(model.errorMessage == "troll est déjà dans la liste.")
        #expect(model.errorTitle == "Pseudo déjà dans la liste")
        #expect(await store.blocklist(for: "moi").count == 1)
    }

    @Test func removingEveryEntryLeavesAnEmptySavedList() async throws {
        let setup = try await fixture(blocklist: ["Un", "Deux"])
        let lists = setup.manager
        let store = setup.store
        let model = PseudoListEditorModel(kind: .blocklist, manager: lists)
        await model.load()
        #expect(model.pseudos == ["Deux", "Un"])
        await model.remove(at: IndexSet(integer: 0)).value
        #expect(model.pseudos == ["Un"])
        await model.remove(at: IndexSet(integer: 0)).value
        #expect(model.pseudos.isEmpty && model.errorMessage == nil)
        #expect(await store.blocklist(for: "moi").isEmpty)
        #expect(await store.loadFailure() == nil)
    }

    /// Two swipes in a row, before the first write ran: each one removes the row the user swiped, and no deleted row comes back.
    @Test func twoQuickSwipesRemoveTheTwoSwipedMembers() async throws {
        let setup = try await fixture(blocklist: ["Un", "Deux", "Trois", "Quatre"])
        let lists = setup.manager
        let store = setup.store
        let model = PseudoListEditorModel(kind: .blocklist, manager: lists)
        await model.load()
        #expect(model.pseudos == ["Deux", "Quatre", "Trois", "Un"])
        let first = model.remove(at: IndexSet(integer: 0)) // Deux
        #expect(model.pseudos == ["Quatre", "Trois", "Un"])
        let second = model.remove(at: IndexSet(integer: 1)) // Trois, as the list now shows it
        #expect(model.pseudos == ["Quatre", "Un"])
        await first.value
        await second.value
        #expect(model.pseudos == ["Quatre", "Un"] && model.errorMessage == nil)
        #expect(await store.blocklist(for: "moi").map(\.pseudo).sorted() == ["Quatre", "Un"])
    }

    /// A read asked for while a swipe's write is held (an add, a retry) waits for every queued write: no swiped row comes back.
    @Test func aReloadDuringQueuedRemovalsWaitsForThemAndKeepsTheRowsGone() async throws {
        let persistence = GatedPersistence()
        let store = PseudoListStore(persistence: persistence)
        for pseudo in ["Un", "Deux", "Trois", "Quatre"] { try await store.block(pseudo, account: "moi") }
        let model = PseudoListEditorModel(kind: .blocklist, manager: PseudoListManager(store: store, account: "moi"))
        await model.load()
        persistence.close()
        let first = model.remove(at: IndexSet(integer: 0)) // Deux, its write is held
        let second = model.remove(at: IndexSet(integer: 1)) // Trois
        let reloaded = Mutex(false)
        let reload = Task { await model.load(); reloaded.withLock { $0 = true } }
        for _ in 0..<20 { await Task.yield() }
        #expect(!reloaded.withLock { $0 }) // the reload does not complete while a removal is held
        #expect(model.pseudos == ["Quatre", "Un"]) // held writes: the list shows the swipes, not the stored file
        persistence.open()
        await reload.value // the reload ran after both writes, not between them
        #expect(model.pseudos == ["Quatre", "Un"])
        await first.value
        await second.value
        #expect(await store.blocklist(for: "moi").map(\.pseudo).sorted() == ["Quatre", "Un"])
    }

    /// A swiped pseudo added back before its queued removal ran is added after the removal: it ends in the list, with no
    /// "already listed" message.
    @Test func addingBackASwipedPseudoWaitsForItsQueuedRemoval() async throws {
        let persistence = GatedPersistence()
        let store = PseudoListStore(persistence: persistence)
        for pseudo in ["Un", "Deux"] { try await store.block(pseudo, account: "moi") }
        let model = PseudoListEditorModel(kind: .blocklist, manager: PseudoListManager(store: store, account: "moi"))
        await model.load()
        persistence.close()
        // Un first, its write held; the removal of Deux then waits behind it, so it has not reached the store when the add does.
        let first = model.remove(at: IndexSet(integer: 1)) // Un
        let second = model.remove(at: IndexSet(integer: 0)) // Deux
        model.draft = "Deux"
        let adding = Task { await model.add() }
        for _ in 0..<20 { await Task.yield() }
        persistence.open()
        await first.value
        await second.value
        await adding.value
        #expect(model.errorMessage == nil)
        #expect(await store.blocklist(for: "moi").map(\.pseudo) == ["Deux"])
        #expect(model.pseudos == ["Deux"])
    }

    /// Text typed while an add waits for the queued removals is kept: the add submits what the field held when the user tapped
    /// "Ajouter", and empties the field only if it still holds that text.
    @Test func textTypedWhileAnAddWaitsForRemovalsIsKept() async throws {
        let persistence = GatedPersistence()
        let store = PseudoListStore(persistence: persistence)
        for pseudo in ["Un", "Deux"] { try await store.block(pseudo, account: "moi") }
        let model = PseudoListEditorModel(kind: .blocklist, manager: PseudoListManager(store: store, account: "moi"))
        await model.load()
        persistence.close()
        let removal = model.remove(at: IndexSet(integer: 0)) // Deux, its write is held
        model.draft = "Trois"
        let adding = Task { await model.add() } // waits for the held removal
        for _ in 0..<20 { await Task.yield() }
        model.draft = "Quatre" // typed during the wait
        persistence.open()
        await removal.value
        await adding.value
        #expect(model.draft == "Quatre") // the newer text is not cleared, nor submitted
        #expect(model.errorMessage == nil)
        #expect(await store.blocklist(for: "moi").map(\.pseudo).sorted() == ["Trois", "Un"])
        #expect(model.pseudos == ["Trois", "Un"])
    }

    /// An unreadable file shows its failure instead of an empty list, refuses the add and writes nothing.
    @Test func anUnreadableFileKeepsTheEditorReadOnly() async throws {
        let persistence = UnreadablePersistence()
        let lists = PseudoListManager(store: PseudoListStore(persistence: persistence), account: "moi")
        let model = PseudoListEditorModel(kind: .allowlist, manager: lists)
        await model.load()
        #expect(model.unreadableMessage != nil && model.pseudos.isEmpty)
        model.draft = "Ami"
        #expect(!model.canAdd)
        await model.add()
        #expect(persistence.saveCount == 0)
    }

    @Test func loggedOutTheBlocklistEditorAsksForAnAccount() async throws {
        let setup = try await fixture(account: nil)
        let lists = setup.manager
        let model = PseudoListEditorModel(kind: .blocklist, manager: lists)
        model.draft = "Troll"
        #expect(model.requiresAccount && !model.canAdd)
    }
}

/// The BL / WL entries of the message menu.
@MainActor
struct PseudoListActionHandlerTests {
    private func context(author: String = "Auteur") -> MessageMenuContext {
        MessageMenuContext(numreponse: 7, author: author, actions: MessageActions())
    }

    @Test func pickingTheEntryTogglesTheAuthorTellsTheUserAndRebuildsThePage() async throws {
        let setup = try await fixture()
        let lists = setup.manager
        let store = setup.store
        var said: [String] = []
        var rebuilt = 0
        let registry = MessageActionRegistry(PseudoListActionHandler.pair(
            manager: lists, confirm: { said.append($0) }, rebuild: { rebuilt += 1 }
        ))
        #expect(registry.offers(.avatar) && !registry.offers(.message))
        #expect(await registry.perform(.blocklist, with: context()))
        #expect(said == ["BIM! Auteur ajouté à la liste noire"] && rebuilt == 1)
        #expect(await store.isBlocked("auteur", account: "moi"))
        #expect(await registry.perform(.allowlist, with: context()))
        #expect(await store.allowlist().map(\.pseudo) == ["Auteur"] && rebuilt == 2)
    }

    @Test func aFailedWriteTellsTheUserAndLeavesThePageAlone() async throws {
        let lists = PseudoListManager(store: PseudoListStore(persistence: UnreadablePersistence()), account: "moi")
        var said: [String] = []
        var rebuilt = 0
        let handler = PseudoListActionHandler(listKind: .blocklist, manager: lists, confirm: { said.append($0) }, rebuild: { rebuilt += 1 })
        await handler.perform(with: context())
        #expect(said.count == 1 && rebuilt == 0)
    }

    @Test func loggedOutOnlyTheAllowlistEntryIsOffered() async throws {
        let setup = try await fixture(account: nil)
        let lists = setup.manager
        let registry = MessageActionRegistry(PseudoListActionHandler.pair(manager: lists, confirm: { _ in }, rebuild: {}))
        let entries = registry.entries(for: context(), source: .avatar)
        #expect(entries == [.allowlist])
    }
}
