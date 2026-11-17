import Foundation
import HFRClient
import HFRModels
import HFRStorage
@testable import SwiftHFR
import Testing

/// LOT-131 across windows (LOT-146): each window has its own log and models over the account's one store, record and copy.
@MainActor
struct BlocklistSyncWindowTests {
    @Test func aRemovalHeldInAnotherWindowIsNotImportedBack() async throws {
        // LOT-146: each window has its own log and model over the account's one store; the held changes are the account's.
        let fixture = try await BlocklistSyncModelTests.make(
            thread: 7, state: .on, copy: BlocklistSyncModelTests.syncedCopy(["Alpha"]), remote: ["Alpha"], local: ["Alpha"]
        )
        let otherWindow = PseudoListManager(
            store: fixture.store, account: MPStorageSyncModelTests.account, blocklistChanges: BlocklistChangeLog(held: fixture.held)
        )
        try await otherWindow.remove("Alpha", from: .blocklist)
        await fixture.base.model.start()
        #expect(await fixture.local().isEmpty)
        #expect(try await fixture.remote.blocklist().isEmpty)
    }

    @Test func everyWindowOfAnAccountSharesItsHeldChanges() {
        let first = HeldBlocklistChanges.shared(for: "Window\u{200B}Test")
        let second = HeldBlocklistChanges.shared(for: "windowtest")
        let other = HeldBlocklistChanges.shared(for: "OtherWindowTest")
        #expect(first === second)
        #expect(first !== other)
    }

    @Test func heldChangesEndWithTheLastWindowThatHoldsThem() {
        var held: HeldBlocklistChanges? = .shared(for: "ClosedWindowTest")
        held?.changes.withLock { $0.append(BlocklistChange(pseudo: "Alpha", added: false)) }
        held = nil
        #expect(HeldBlocklistChanges.shared(for: "ClosedWindowTest").changes.withLock { $0 }.isEmpty)
    }

    /// A second window's model of the same account, built while the account was still `unasked`.
    static func otherWindow(of fixture: BlocklistSyncModelTests.Fixture) -> BlocklistSyncModel {
        let model = MPStorageSyncModel(
            account: MPStorageSyncModelTests.account,
            sync: MPStorageSync(remote: fixture.remote, persistence: fixture.base.persistence),
            states: fixture.base.states, isLoggedIn: { true }, clock: { MPStorageSyncModelTests.now }
        )
        return BlocklistSyncModel(
            mpStorage: model, store: fixture.store, changes: BlocklistChangeLog(held: fixture.held), refreshLists: {}
        )
    }

    @Test func aWindowWritesWithoutAskingOnceAnotherWindowSwitchedOn() async throws {
        let fixture = try await BlocklistSyncModelTests.make(thread: 7, state: .unasked)
        let other = Self.otherWindow(of: fixture)
        await fixture.base.model.setEnabled(true)
        #expect(fixture.base.model.isOn)
        try await fixture.manager.add("Alpha", to: .blocklist)
        await other.handle(BlocklistChange(pseudo: "Alpha", added: true))
        #expect(!other.asksConsent)
        #expect(try await fixture.remote.blocklist() == ["Alpha"])
    }

    @Test func aLateNoInAnotherWindowNeverOverwritesTheChoiceMade() async throws {
        let fixture = try await BlocklistSyncModelTests.make(thread: 7, state: .unasked)
        let other = Self.otherWindow(of: fixture)
        // The question shows in the other window; meanwhile this one switches on.
        await fixture.base.model.setEnabled(true)
        await other.answerConsent(false)
        #expect(fixture.base.states.record(for: MPStorageSyncModelTests.account)?.state == .on)
    }
}
