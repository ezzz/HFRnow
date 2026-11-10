import Foundation
import HFRModels
import Testing
@testable import HFRStorage

/// The switch, bootstrap and divergence rules of ADR 0013 §6 (LOT-173), on in-memory items shared by simulated devices.
@Suite struct AccountSyncTests {
    let item = InMemorySecureDataItem()

    // MARK: - Switch

    @Test func offByDefaultNothingIsEverWrittenToTheSynchronizableItem() throws {
        let device = try SyncDevice(item: item, accounts: [fakeAccount("user-a")])
        try device.reconcile(at: 10)
        try device.logIn("user-b", at: 20)
        try device.refresh("user-a", cookie: "fake-2", at: 30)
        try device.remove("user-b", at: 40)
        #expect(item.data == nil)
        #expect(item.writeCount == 0)
        #expect(!device.isOn)
    }

    @Test func switchingOnOverAnAbsentItemWritesOneFullEnvelope() throws {
        let device = try SyncDevice(item: item, accounts: [fakeAccount("user-a")])
        let report = try device.switchOn(at: 100)
        #expect(report.itemWritten)
        #expect(try item.envelope?.enabledAt == moment(100))
        #expect(item.sharedPseudos == ["user-a"])
        #expect(device.sync.state().enabledAt == moment(100))
        #expect(device.isOn)
    }

    @Test func switchingOffWritesATombstoneAndKeepsTheAccountsEnteredHere() throws {
        let device = try SyncDevice(item: item, accounts: [fakeAccount("user-a")])
        try device.switchOn(at: 100)
        let before = device.accounts.envelope
        try device.switchOff(at: 150)
        #expect(try item.envelope == .tombstone(deletedAt: moment(150)))
        #expect(item.data != nil)
        #expect(device.accounts.envelope == before)
        #expect(!device.isOn)
        #expect(device.sync.state().honouredDeletedAt == moment(150))
    }

    @Test func aTombstoneHoldsNoCredential() throws {
        let data = try AccountSyncEnvelope.tombstone(deletedAt: moment(150)).encoded()
        #expect(String(data: data, encoding: .utf8) == #"{"accounts":[],"deletedAt":150,"version":1}"#)
    }

    @Test func aSwitchOnOverAFullEnvelopeAdoptsItsVersionAndBothDevicesStayOn() throws {
        let deviceA = try SyncDevice(item: item, accounts: [fakeAccount("user-a")])
        let deviceB = try SyncDevice(item: item, accounts: [fakeAccount("user-b")])
        try deviceA.switchOn(at: 100)
        try deviceB.switchOn(at: 120)
        #expect(deviceB.sync.state().enabledAt == moment(100))
        #expect(item.sharedPseudos == ["user-a", "user-b"])
        #expect(deviceB.pseudos == ["user-b", "user-a"])
        let report = try deviceA.reconcile(at: 130)
        #expect(report.replaced == ["user-b"])
        #expect(deviceA.pseudos == ["user-a", "user-b"])
        #expect(deviceA.isOn && deviceB.isOn)
    }

    @Test func theMainAccountStaysEachDevicesOwn() throws {
        let deviceA = try SyncDevice(item: item, accounts: [fakeAccount("user-a")])
        let deviceB = try SyncDevice(item: item, accounts: [fakeAccount("user-b")])
        try deviceA.switchOn(at: 100)
        try deviceB.switchOn(at: 120)
        try deviceA.reconcile(at: 130)
        #expect(try deviceA.accounts.mainAccount()?.pseudo == "user-a")
        #expect(try deviceB.accounts.mainAccount()?.pseudo == "user-b")
    }

    // MARK: - Bootstrap

    @Test func aFreshDeviceImportsAFullEnvelopeAndKeepsItsOwnItemAsMasterAfterwards() throws {
        let deviceA = try SyncDevice(item: item, accounts: [fakeAccount("user-a")])
        try deviceA.switchOn(at: 100)
        let fresh = try SyncDevice(item: item)
        let report = try fresh.reconcile(at: 110)
        #expect(report.bootstrapped)
        #expect(fresh.pseudos == ["user-a"])
        #expect(fresh.isOn)
        #expect(fresh.sync.state().enabledAt == moment(100))
        #expect(fresh.sync.state().isProvisional)
        // The confirming read ends the provisional state; the device's own item is the master from then on.
        try fresh.reconcile(at: 120)
        #expect(!fresh.sync.state().isProvisional)
        try fresh.refresh("user-a", cookie: "fake-fresh", at: 130)
        #expect(fresh.cookie(of: "user-a") == "fake-fresh")
        try deviceA.reconcile(at: 140)
        #expect(deviceA.cookie(of: "user-a") == "fake-fresh")
    }

    @Test func aFreshDeviceThatFindsATombstoneImportsNothingAndCreatesNoAccountsItem() throws {
        item.data = try AccountSyncEnvelope.tombstone(deletedAt: moment(150)).encoded()
        let fresh = try SyncDevice(item: item)
        try fresh.reconcile(at: 160)
        #expect(!fresh.isOn)
        #expect(fresh.sync.state().honouredDeletedAt == moment(150))
        #expect(fresh.accounts.envelope == nil)
    }

    @Test func aFreshDeviceThatKnowsALaterTombstoneRefusesAnEnvelope() throws {
        item.data = try AccountSyncEnvelope.tombstone(deletedAt: moment(150)).encoded()
        let fresh = try SyncDevice(item: item)
        try fresh.reconcile(at: 160)
        item.data = try AccountSyncEnvelope.full(
            enabledAt: moment(150), accounts: [SyncedAccount(account: fakeAccount("user-a"), stamp: .unknown)], removed: [:]
        ).encoded()
        let report = try fresh.reconcile(at: 170)
        #expect(!report.bootstrapped)
        #expect(fresh.accounts.envelope == nil)
        #expect(!fresh.isOn)
        // And it repairs the race: the tombstone is back.
        #expect(try item.envelope == .tombstone(deletedAt: moment(150)))
    }

    @Test func anAbsentItemNeverActs() throws {
        let device = try SyncDevice(item: item, accounts: [fakeAccount("user-a")])
        try device.switchOn(at: 100)
        item.data = nil
        let report = try device.refresh("user-a", cookie: "fake-2", at: 110)
        #expect(report == AccountSyncReport())
        #expect(item.data == nil)
        #expect(device.isOn)
    }

    // MARK: - Write side and race repair

    /// ADR 0013 §6 *Race repair*: A reads, B writes the tombstone (150), A writes its stale envelope (160), B repairs,
    /// A switches off.
    @Test func aStaleWriteOverATombstoneIsRepairedAndSwitchesTheWriterOff() throws {
        let deviceA = try SyncDevice(item: item, accounts: [fakeAccount("user-a")])
        let deviceB = try SyncDevice(item: item)
        try deviceA.switchOn(at: 100)
        try deviceB.reconcile(at: 110)
        try deviceB.reconcile(at: 120)
        item.beforeNextWrite { _ = try? deviceB.switchOff(at: 150) }
        try deviceA.refresh("user-a", cookie: "fake-2", at: 160)
        #expect(try item.envelope?.enabledAt == moment(100))

        let repair = try deviceB.reconcile(at: 170)
        #expect(repair.itemWritten)
        #expect(try item.envelope == .tombstone(deletedAt: moment(150)))
        let off = try deviceA.reconcile(at: 180)
        #expect(off.switchedOff == .tombstone)
        #expect(!deviceA.isOn)
        #expect(deviceA.pseudos == ["user-a"])
        // Sync never comes back without an explicit switch-on.
        try deviceA.logIn("user-c", at: 190)
        try deviceA.reconcile(at: 200)
        #expect(try item.envelope == .tombstone(deletedAt: moment(150)))
    }

    /// Every push is a read-compare-write: a tombstone written between the read and the write is never overwritten.
    @Test func aPushNeverOverwritesWhatAnotherDeviceWroteAfterItsRead() throws {
        let deviceA = try SyncDevice(item: item, accounts: [fakeAccount("user-a")])
        let deviceB = try SyncDevice(item: item)
        try deviceA.switchOn(at: 100)
        try deviceB.reconcile(at: 110)
        item.afterNextRead { _ = try? deviceB.switchOff(at: 150) }
        let report = try deviceA.refresh("user-a", cookie: "fake-2", at: 160)
        #expect(!report.itemWritten)
        #expect(try item.envelope == .tombstone(deletedAt: moment(150)))
        #expect(try deviceA.reconcile(at: 170).switchedOff == .tombstone)
    }

    @Test func aTombstoneDatedAtTheDevicesSwitchOnSwitchesItOff() throws {
        let device = try SyncDevice(item: item, accounts: [fakeAccount("user-a")])
        try device.switchOn(at: 100)
        item.data = try AccountSyncEnvelope.tombstone(deletedAt: moment(100)).encoded()
        let report = try device.reconcile(at: 110)
        #expect(report.switchedOff == .tombstone)
        #expect(!device.isOn)
    }

    @Test func aLaterSwitchOnSwitchesTheDeviceOffAndRefusesItsPush() throws {
        let device = try SyncDevice(item: item, accounts: [fakeAccount("user-a")])
        try device.switchOn(at: 100)
        let later = try AccountSyncEnvelope.full(
            enabledAt: moment(200), accounts: [SyncedAccount(account: fakeAccount("user-b"), stamp: .unknown)], removed: [:]
        ).encoded()
        item.data = later
        let report = try device.refresh("user-a", cookie: "fake-2", at: 210)
        #expect(report.switchedOff == .laterSwitchOn)
        #expect(!report.itemWritten)
        #expect(item.data == later)
        #expect(!device.isOn)
        #expect(device.pseudos == ["user-a"])
    }

    @Test func aDeviceSwitchedOnAfterATombstoneRewritesItsEnvelopeOverIt() throws {
        let device = try SyncDevice(item: item, accounts: [fakeAccount("user-a")])
        item.data = try AccountSyncEnvelope.tombstone(deletedAt: moment(150)).encoded()
        try device.switchOn(at: 140)
        // Its switch-on is strictly later than the tombstone, even with a clock behind.
        #expect(try #require(device.sync.state().enabledAt) > moment(150))
        item.data = try AccountSyncEnvelope.tombstone(deletedAt: moment(150)).encoded()
        let report = try device.reconcile(at: 160)
        #expect(report.itemWritten)
        #expect(item.sharedPseudos == ["user-a"])
        #expect(device.isOn)
    }

    @Test func aStaleEnvelopeIsOverwrittenWithoutLoweringTheVersion() throws {
        let device = try SyncDevice(item: item, accounts: [fakeAccount("user-a")])
        try device.switchOn(at: 200)
        item.data = try AccountSyncEnvelope.full(enabledAt: moment(100), accounts: [], removed: [:]).encoded()
        try device.reconcile(at: 210)
        #expect(try item.envelope?.enabledAt == moment(200))
        #expect(item.sharedPseudos == ["user-a"])
    }

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
        #expect(!fresh.sync.state().isProvisional)
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

    @Test func switchingOffWritesItsTombstoneOverAnUnreadableItem() throws {
        let device = try SyncDevice(item: item, accounts: [fakeAccount("user-a")])
        try device.switchOn(at: 100)
        item.data = Data("not json".utf8)
        try device.switchOff(at: 150)
        #expect(try item.envelope == .tombstone(deletedAt: moment(150)))
    }
}
