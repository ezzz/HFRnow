import Foundation
import HFRModels
import Testing
@testable import HFRStorage

/// #1200 P3: an absent state item is a device that never shared its accounts. A state a later version wrote is refused and
/// never written over, so a rollback cannot erase the switch and the tombstones it honoured, nor let the device bootstrap
/// again after an opt-out. Damaged bytes are refused the same way, except by the user's explicit switch-off, which resets
/// them to off (operator option (b) on #1200): never silently, never the accounts, never the iCloud item.
@Suite struct AccountSyncUnreadableStateTests {
    let item = InMemorySecureDataItem()

    /// What a later version could write: a version this one does not know, with the fields of today's.
    static let laterVersion = Data(#"{"version":2,"isOn":false,"honouredDeletedAt":150,"hadLocalAccounts":true}"#.utf8)
    /// Bytes no version writes as they are: not JSON, JSON without a version, a version of another type, today's version
    /// without its required fields.
    static let damaged = [
        Data("garbage".utf8), Data(#"{"isOn":true}"#.utf8), Data(#"{"version":"1","isOn":true}"#.utf8),
        Data(#"{"version":1}"#.utf8)
    ]

    @Test func anAbsentStateIsOffAndIsWrittenOnTheFirstChange() throws {
        let device = try SyncDevice(item: item, accounts: [fakeAccount("user-a")])
        #expect(device.state.data == nil)
        #expect(try device.sync.state() == AccountSyncState())
        try device.logIn("user-b", at: 20)
        #expect(try device.sync.state().hadLocalAccounts)
        #expect(device.state.writeCount == 1)
    }

    @Test("A state a later version wrote is refused by every operation, the switch-off included, and kept")
    func aLaterVersionStateIsRefusedAndKept() throws {
        let device = try SyncDevice(item: item, accounts: [fakeAccount("user-a")])
        device.state.data = Self.laterVersion
        let refused = AccountSyncError.stateFromLaterVersion
        #expect(throws: refused) { try device.sync.state() }
        #expect(throws: refused) { try device.reconcile(at: 10) }
        #expect(throws: refused) { try device.logIn("user-b", at: 20) }
        #expect(throws: refused) { try device.remove("user-a", at: 30) }
        #expect(throws: refused) { try device.switchOn(at: 40) }
        #expect(throws: refused) { try device.sync.switchOff() }
        #expect(device.state.data == Self.laterVersion)
        #expect(device.state.writeCount == 0)
        #expect(item.writeCount == 0)
    }

    @Test("Damaged state bytes are refused by every operation but the switch-off, and kept", arguments: Self.damaged)
    func aDamagedStateIsRefusedAndKept(stored: Data) throws {
        let device = try SyncDevice(item: item, accounts: [fakeAccount("user-a")])
        device.state.data = stored
        let refused = AccountSyncError.damagedState
        #expect(throws: refused) { try device.sync.state() }
        #expect(throws: refused) { try device.reconcile(at: 10) }
        #expect(throws: refused) { try device.logIn("user-b", at: 20) }
        #expect(throws: refused) { try device.remove("user-a", at: 30) }
        #expect(throws: refused) { try device.switchOn(at: 40) }
        #expect(device.state.data == stored)
        #expect(device.state.writeCount == 0)
        #expect(item.writeCount == 0)
    }

    @Test("The user's switch-off resets damaged state bytes to off: the accounts and the iCloud item are untouched",
          arguments: Self.damaged)
    func theSwitchOffResetsADamagedState(stored: Data) throws {
        let other = try SyncDevice(item: item, accounts: [fakeAccount("user-z")])
        try other.switchOn(at: 100)
        let shared = item.data
        let device = try SyncDevice(item: item, accounts: [fakeAccount("user-a")])
        device.state.data = stored
        let report = try device.sync.switchOff()
        #expect(report == AccountSyncReport())
        var expected = AccountSyncState()
        expected.hadLocalAccounts = true
        #expect(try device.sync.state() == expected)
        #expect(device.state.writeCount == 1)
        #expect(item.data == shared)
        #expect(device.pseudos == ["user-a"])
        // Consented once: the reset device never imports another device's accounts by itself.
        let after = try device.reconcile(at: 110)
        #expect(!after.bootstrapped)
        #expect(device.pseudos == ["user-a"])
        #expect(!device.isOn)
    }

    @Test("A reset device with no account of its own does not import another device's accounts by itself")
    func aResetDeviceWithoutAccountsNeverBootstraps() throws {
        let other = try SyncDevice(item: item, accounts: [fakeAccount("user-z")])
        try other.switchOn(at: 100)
        let device = try SyncDevice(item: item)
        device.state.data = Data("garbage".utf8)
        try device.sync.switchOff()
        let after = try device.reconcile(at: 110)
        #expect(!after.bootstrapped)
        #expect(device.pseudos.isEmpty)
        #expect(!device.isOn)
    }

    @Test("A device whose state a later version wrote after an opt-out does not bootstrap from another device's envelope")
    func anUnreadableStateNeverBootstraps() throws {
        let other = try SyncDevice(item: item, accounts: [fakeAccount("user-a")])
        try other.switchOn(at: 200)
        let rolledBack = try SyncDevice(item: item)
        rolledBack.state.data = Self.laterVersion
        #expect(throws: AccountSyncError.stateFromLaterVersion) { try rolledBack.reconcile(at: 210) }
        #expect(rolledBack.pseudos.isEmpty)
        #expect(rolledBack.state.data == Self.laterVersion)
    }
}
