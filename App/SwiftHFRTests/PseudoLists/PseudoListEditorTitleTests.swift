import Foundation
import HFRModels
import HFRStorage
@testable import SwiftHFR
import Synchronization
import Testing

/// A persistence that reads fine and refuses every write once `refuseWrites()` was called.
private final class FailingSavePersistence: PseudoListPersistence {
    private let inner = InMemoryPseudoListPersistence()
    private let refusing = Mutex(false)
    func refuseWrites() { refusing.withLock { $0 = true } }
    func load() throws -> PseudoListDocument? { try inner.load() }
    func save(_ document: PseudoListDocument) throws {
        if refusing.withLock({ $0 }) { throw CocoaError(.fileWriteUnknown) }
        try inner.save(document)
    }
    func quarantineUnreadableData() throws { try inner.quarantineUnreadableData() }
}

/// A persistence whose file cannot be read nor set aside.
private final class UnrecoverablePersistence: PseudoListPersistence {
    func load() throws -> PseudoListDocument? { throw CocoaError(.fileReadCorruptFile) }
    func save(_ document: PseudoListDocument) throws {}
    func quarantineUnreadableData() throws { throw CocoaError(.fileWriteNoPermission) }
}

/// #1175: the alert titles of the pseudo editors.
@MainActor @Suite(.timeLimit(.minutes(5)))
struct PseudoListEditorTitleTests {
    /// #1175: the alert's title says what failed, never « Erreur », and a later failure never keeps an earlier title.
    @Test func aRefusedAddAfterADuplicateSaysAddFailedNotAlreadyListed() async throws {
        let persistence = FailingSavePersistence()
        let store = PseudoListStore(persistence: persistence)
        try await store.block("Troll", account: "moi")
        let model = PseudoListEditorModel(kind: .blocklist, manager: PseudoListManager(store: store, account: "moi"))
        await model.load()
        model.draft = "troll"
        await model.add()
        #expect(model.errorTitle == "Pseudo déjà dans la liste")
        persistence.refuseWrites()
        model.draft = "Autre"
        await model.add()
        #expect(model.errorMessage == PseudoListKind.blocklist.addFailure)
        #expect(model.errorTitle == "Ajout impossible")
    }

    @Test func aRefusedRemovalSaysRemovalFailedInTheTitle() async throws {
        let persistence = FailingSavePersistence()
        let store = PseudoListStore(persistence: persistence)
        try await store.block("Troll", account: "moi")
        let model = PseudoListEditorModel(kind: .blocklist, manager: PseudoListManager(store: store, account: "moi"))
        await model.load()
        model.draft = "Ami" // sorts first: the swiped row
        await model.add()
        persistence.refuseWrites()
        await model.remove(at: IndexSet(integer: 0)).value
        #expect(model.errorMessage == PseudoListKind.blocklist.removeFailure("Ami"))
        #expect(model.errorTitle == "Suppression impossible")
    }

    @Test func aRefusedResetSaysResetFailedInTheTitle() async {
        let store = PseudoListStore(persistence: UnrecoverablePersistence())
        let model = PseudoListEditorModel(kind: .blocklist, manager: PseudoListManager(store: store, account: "moi"))
        await model.discardUnreadable()
        #expect(model.errorMessage == UnreadableDataRecovery.failure)
        #expect(model.errorTitle == "Réinitialisation impossible")
    }
}
