import Foundation
import HFRModels
import Testing
@testable import HFRStorage

/// The merge, the provisional bootstrap and the unreadable item of ADR 0013 §6 (LOT-173), on in-memory items shared by
/// simulated devices. Split from `AccountSyncTests` for length.
@Suite struct AccountSyncMergeTests {
    let item = InMemorySecureDataItem()

    // MARK: - Merge

    /// #312: the device holding the newest account reads the union written by the other one, with the same newest date.
    @Test func anUpdatedAtTieNeverLeavesTheOtherDevicesAccountsUnshared() throws {
        let deviceA = try SyncDevice(item: item)
        let deviceB = try SyncDevice(item: item)
        try deviceB.logIn("user-b", at: 90)
        try deviceA.logIn("user-a", at: 95)
        try deviceA.switchOn(at: 100)
        try deviceA.refresh("user-a", cookie: "fake-2", at: 130)
        try deviceB.switchOn(at: 140)
        #expect(item.sharedPseudos == ["user-a", "user-b"])
        try deviceA.reconcile(at: 150)
        #expect(deviceA.pseudos == ["user-a", "user-b"])
        #expect(deviceA.cookie(of: "user-a") == "fake-2")
    }

    @Test func aReloginOnAnotherDeviceReplacesTheCredentials() throws {
        let deviceA = try SyncDevice(item: item, accounts: [fakeAccount("user-a")])
        try deviceA.switchOn(at: 100)
        let deviceB = try SyncDevice(item: item)
        try deviceB.reconcile(at: 110)
        try deviceB.logIn("user-a", cookie: "fake-new", at: 120)
        let report = try deviceA.reconcile(at: 130)
        #expect(report.replaced == ["user-a"])
        #expect(deviceA.cookie(of: "user-a") == "fake-new")
    }

    @Test func aRemovalWhileOnReachesTheOtherDevices() throws {
        let deviceA = try SyncDevice(item: item, accounts: [fakeAccount("user-a"), fakeAccount("user-x")])
        try deviceA.switchOn(at: 100)
        let deviceB = try SyncDevice(item: item)
        try deviceB.reconcile(at: 110)
        try deviceA.remove("user-x", at: 120)
        let report = try deviceB.reconcile(at: 130)
        #expect(report.dropped == ["user-x"])
        #expect(deviceB.pseudos == ["user-a"])
    }

    /// #312 per-account consent: D switched off while holding y, y deleted on B, D switched on again: y does not return,
    /// even with cookies refreshed after the deletion; an explicit login does bring it back.
    @Test func aMergeNeverBringsBackAnAccountDeletedOnAnotherDevice() throws {
        let deviceB = try SyncDevice(item: item)
        let deviceD = try SyncDevice(item: item)
        try deviceB.logIn("user-b", at: 10)
        try deviceB.logIn("user-y", at: 20)
        try deviceB.switchOn(at: 100)
        try deviceD.reconcile(at: 105)
        try deviceD.reconcile(at: 106)
        try deviceD.switchOff(at: 150)
        try deviceB.reconcile(at: 160)
        try deviceB.switchOn(at: 200)
        try deviceB.remove("user-y", at: 210)
        try deviceD.refresh("user-y", cookie: "fake-refreshed", at: 220)
        let report = try deviceD.switchOn(at: 230)
        #expect(!item.sharedPseudos.contains("user-y"))
        #expect(report.dropped == ["user-y"])
        #expect(deviceD.pseudos == ["user-b"])
        try deviceB.logIn("user-y", at: 240)
        try deviceD.reconcile(at: 250)
        #expect(deviceD.pseudos == ["user-b", "user-y"])
    }

    // MARK: - Provisional bootstrap

    private func racedEnvelope() throws -> (deviceB: SyncDevice, fresh: SyncDevice) {
        let deviceA = try SyncDevice(item: item, accounts: [fakeAccount("user-a")])
        let deviceB = try SyncDevice(item: item)
        try deviceA.switchOn(at: 100)
        try deviceB.reconcile(at: 110)
        try deviceB.reconcile(at: 120)
        item.beforeNextWrite { _ = try? deviceB.switchOff(at: 150) }
        try deviceA.refresh("user-a", cookie: "fake-2", at: 160)
        let fresh = try SyncDevice(item: item)
        #expect(try fresh.reconcile(at: 165).bootstrapped)
        return (deviceB, fresh)
    }

    @Test func aRepairWhileProvisionalDropsTheImportedAccountsOnly() throws {
        let (deviceB, fresh) = try racedEnvelope()
        try fresh.logIn("user-own", at: 166)
        try deviceB.reconcile(at: 170)
        let report = try fresh.reconcile(at: 180)
        #expect(report.switchedOff == .tombstone)
        #expect(report.dropped == ["user-a"])
        #expect(fresh.pseudos == ["user-own"])
    }

    @Test func aRepairAfterTheProvisionalWindowDeletesNothing() throws {
        let (deviceB, fresh) = try racedEnvelope()
        try fresh.reconcile(at: 166)
        #expect(try !fresh.sync.state().isProvisional)
        try deviceB.reconcile(at: 170)
        let report = try fresh.reconcile(at: 180)
        #expect(report.switchedOff == .tombstone)
        #expect(report.dropped.isEmpty)
        #expect(fresh.pseudos == ["user-a"])
    }

    @Test func switchingOffWhileProvisionalDropsTheImportedAccounts() throws {
        let deviceA = try SyncDevice(item: item, accounts: [fakeAccount("user-a")])
        try deviceA.switchOn(at: 100)
        let fresh = try SyncDevice(item: item)
        try fresh.reconcile(at: 110)
        let report = try fresh.switchOff(at: 120)
        #expect(report.dropped == ["user-a"])
        #expect(fresh.pseudos.isEmpty)
    }

    // MARK: - Unreadable item

    @Test(arguments: [Data("not json".utf8), Data(#"{"version":2,"accounts":[]}"#.utf8)])
    func anUnreadableItemIsNeverOverwrittenExceptBySwitchingOff(bytes: Data) throws {
        let device = try SyncDevice(item: item, accounts: [fakeAccount("user-a")])
        item.data = bytes
        #expect(throws: CredentialStoreError.self) { try device.switchOn(at: 100) }
        #expect(item.data == bytes)
        #expect(!device.isOn)
        #expect(throws: CredentialStoreError.self) { try device.reconcile(at: 110) }
        #expect(item.data == bytes)
    }

    /// A Keychain refusal on the state item (device locked before its first unlock) stops the operation: read as "off",
    /// the next save would erase the switch and the tombstones it honoured.
    @Test func aStateTheKeychainRefusesStopsEveryOperation() throws {
        struct Refusing: SecureDataItem {
            func read() throws -> Data? { throw CredentialStoreError.keychain(status: -25_308) }
            func write(_ data: Data) throws { throw CredentialStoreError.keychain(status: -25_308) }
        }
        item.data = try AccountSyncEnvelope.full(
            enabledAt: moment(100), accounts: [SyncedAccount(account: fakeAccount("user-a"), stamp: .unknown)], removed: [:]
        ).encoded()
        let before = item.data
        let accounts = InMemoryCredentialStore()
        let sync = AccountSync(accounts: accounts, item: item, state: Refusing())
        #expect(throws: CredentialStoreError.keychain(status: -25_308)) { try sync.reconcile() }
        #expect(throws: CredentialStoreError.keychain(status: -25_308)) { try sync.switchOn() }
        #expect(throws: CredentialStoreError.keychain(status: -25_308)) { try sync.localChange(.login(pseudo: "user-b")) }
        #expect(accounts.envelope == nil)
        #expect(item.data == before)
    }

    @Test func switchingOffWritesItsTombstoneOverAnUnreadableItem() throws {
        let device = try SyncDevice(item: item, accounts: [fakeAccount("user-a")])
        try device.switchOn(at: 100)
        item.data = Data("not json".utf8)
        try device.switchOff(at: 150)
        #expect(try item.envelope == .tombstone(deletedAt: moment(150)))
    }
}
