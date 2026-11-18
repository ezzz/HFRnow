import Foundation
import HFRModels
import Testing
@testable import HFRStorage

/// #1200 P3: an absent state item is a device that never shared its accounts; an unreadable one (a later version's, or
/// damaged bytes) is refused and never written over, so a rollback cannot erase the switch and the tombstones it
/// honoured, nor let the device bootstrap again after an opt-out.
@Suite struct AccountSyncUnreadableStateTests {
    let item = InMemorySecureDataItem()

    /// What a later version could write: a version this one does not know, with the fields of today's.
    static let laterVersion = Data(#"{"version":2,"isOn":false,"honouredDeletedAt":150,"hadLocalAccounts":true}"#.utf8)
    static let damaged = Data("garbage".utf8)

    @Test func anAbsentStateIsOffAndIsWrittenOnTheFirstChange() throws {
        let device = try SyncDevice(item: item, accounts: [fakeAccount("user-a")])
        #expect(device.state.data == nil)
        #expect(try device.sync.state() == AccountSyncState())
        try device.logIn("user-b", at: 20)
        #expect(try device.sync.state().hadLocalAccounts)
        #expect(device.state.writeCount == 1)
    }

    @Test(arguments: [Self.laterVersion, Self.damaged])
    func anUnreadableStateIsRefusedAndKept(stored: Data) throws {
        let device = try SyncDevice(item: item, accounts: [fakeAccount("user-a")])
        device.state.data = stored
        #expect(throws: AccountSyncError.unreadableState) { try device.sync.state() }
        #expect(throws: AccountSyncError.unreadableState) { try device.reconcile(at: 10) }
        #expect(throws: AccountSyncError.unreadableState) { try device.logIn("user-b", at: 20) }
        #expect(throws: AccountSyncError.unreadableState) { try device.remove("user-a", at: 30) }
        #expect(throws: AccountSyncError.unreadableState) { try device.switchOn(at: 40) }
        #expect(throws: AccountSyncError.unreadableState) { try device.sync.switchOff() }
        #expect(device.state.data == stored)
        #expect(device.state.writeCount == 0)
        #expect(item.writeCount == 0)
        #expect(!device.isOn)
    }

    @Test("A device whose state a later version wrote after an opt-out does not bootstrap from another device's envelope")
    func anUnreadableStateNeverBootstraps() throws {
        let other = try SyncDevice(item: item, accounts: [fakeAccount("user-a")])
        try other.switchOn(at: 200)
        let rolledBack = try SyncDevice(item: item)
        rolledBack.state.data = Self.laterVersion
        #expect(throws: AccountSyncError.unreadableState) { try rolledBack.reconcile(at: 210) }
        #expect(rolledBack.pseudos.isEmpty)
        #expect(rolledBack.state.data == Self.laterVersion)
    }
}
