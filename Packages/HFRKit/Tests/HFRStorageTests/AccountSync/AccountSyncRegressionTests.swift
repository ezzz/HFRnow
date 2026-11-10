import Foundation
import HFRModels
import Testing
@testable import HFRStorage

/// Reads through to `inner`; every write throws while `fail` holds data.
struct ThrowingOnceItem: SecureDataItem {
    let inner: InMemorySecureDataItem
    let fail: InMemorySecureDataItem
    func read() throws -> Data? { try inner.read() }
    func write(_ data: Data) throws {
        if fail.data != nil { throw CredentialStoreError.corrupted }
        try inner.write(data)
    }
}

/// Round 1 of the adversarial review (PR #760): consent of a device that held accounts, item-first switch-on, and the
/// mutations that survived.
@Suite struct AccountSyncProbeTests {
    // P1: a device that never opted in logs out of its last account; the next foreground brings it back and opts in.
    @Test func p1LogoutOnANeverOptedInDevice() throws {
        let item = InMemorySecureDataItem()
        let deviceA = try SyncDevice(item: item, accounts: [fakeAccount("x")])
        try deviceA.switchOn(at: 100)
        let deviceB = try SyncDevice(item: item, accounts: [fakeAccount("x")])
        try deviceB.reconcile(at: 110)
        #expect(!deviceB.isOn)
        try deviceB.remove("x", at: 120)
        #expect(deviceB.pseudos == [])
        try deviceB.reconcile(at: 130)
        #expect(deviceB.pseudos == [], "logged-out account came back")
        #expect(!deviceB.isOn, "device opted in by itself")
    }

    // P1b: a device the user explicitly switched off, then logged out; another device switches on again.
    @Test func p1bExplicitOptOutThenLogout() throws {
        let item = InMemorySecureDataItem()
        let deviceA = try SyncDevice(item: item, accounts: [fakeAccount("x")])
        try deviceA.switchOn(at: 100)
        let deviceB = try SyncDevice(item: item, accounts: [fakeAccount("y")])
        try deviceB.switchOn(at: 110)
        try deviceB.switchOff(at: 120)
        try deviceA.reconcile(at: 130)
        try deviceA.switchOn(at: 140)
        try deviceB.remove("y", at: 150)
        try deviceB.remove("x", at: 151)
        #expect(deviceB.pseudos == [])
        try deviceB.reconcile(at: 160)
        #expect(deviceB.pseudos == [], "accounts came back after explicit opt-out + logout")
        #expect(!deviceB.isOn)
    }

    // P2: switch-on over a full envelope whose write fails: the device stays off but keeps the other device's accounts.
    @Test func p2FailedSwitchOnLeavesForeignAccounts() throws {
        let inner = InMemorySecureDataItem()
        let deviceA = try SyncDevice(item: inner, accounts: [fakeAccount("x")])
        try deviceA.switchOn(at: 100)
        let fail = InMemorySecureDataItem(data: Data([1]))
        let store = try InMemoryCredentialStore(accounts: [fakeAccount("y")])
        let sync = AccountSync(
            accounts: store, item: ThrowingOnceItem(inner: inner, fail: fail), state: InMemorySecureDataItem(), clock: { moment(110) }
        )
        #expect(throws: (any Error).self) { try sync.switchOn() }
        #expect(try !sync.state().isOn)
        #expect(try store.accounts().map(\.pseudo) == ["y"], "foreign account imported although the switch-on failed")
    }

    // P3: A opts out while B's switch-on is between its merge and its write: B keeps and re-shares A's account.
    @Test func p3OptOutRacingASwitchOn() throws {
        let item = InMemorySecureDataItem()
        let deviceA = try SyncDevice(item: item, accounts: [fakeAccount("x")])
        try deviceA.switchOn(at: 100)
        let deviceB = try SyncDevice(item: item, accounts: [fakeAccount("y")])
        item.afterNextRead { _ = try? deviceA.switchOff(at: 105) }
        try deviceB.switchOn(at: 110)
        #expect(deviceB.pseudos == ["y"], "A's account kept on B after A opted out")
        #expect(item.sharedPseudos == ["y"], "A's account re-shared after A opted out")
    }

    /// D8: a re-login of an imported account makes it the device's own; a provisional switch-off keeps it.
    @Test func aReloginOfAnImportedAccountIsNeverDroppedByAProvisionalSwitchOff() throws {
        let item = InMemorySecureDataItem()
        let deviceA = try SyncDevice(item: item, accounts: [fakeAccount("user-a"), fakeAccount("user-b")])
        try deviceA.switchOn(at: 100)
        let fresh = try SyncDevice(item: item)
        try fresh.reconcile(at: 110)
        try fresh.logIn("user-a", cookie: "fake-own", at: 120)
        let report = try fresh.switchOff(at: 130)
        #expect(report.dropped == ["user-b"])
        #expect(fresh.pseudos == ["user-a"])
    }

    /// A removal dated exactly at the copy's last login wins (a tie fails closed).
    @Test func aRemovalAtTheSameDateAsTheLoginRemoves() {
        let entry = SyncedAccount(account: fakeAccount("user-y"), stamp: AccountStamp(credentialsAt: moment(50), consentAt: moment(50)))
        let merge = AccountSyncMerge(
            local: AccountBook(), stamps: [:], localRemoved: [:], remote: [entry], remoteRemoved: ["user-y": moment(50)]
        )
        #expect(merge.book.accounts.isEmpty)
        #expect(merge.removed == ["user-y": moment(50)])
    }

    /// A clock behind the switch-on still writes a tombstone that switches the other devices off (`deletedAt >= enabledAt`).
    @Test func aSwitchOffWithAClockBehindIsNeverEarlierThanTheSwitchOn() throws {
        let item = InMemorySecureDataItem()
        let device = try SyncDevice(item: item, accounts: [fakeAccount("user-a")])
        try device.switchOn(at: 100)
        try device.switchOff(at: 90)
        #expect(try item.envelope == .tombstone(deletedAt: moment(100)))
    }

    /// A removal while off is this device's own business: it is not shared at the next switch-on (spec, per-account dates).
    @Test func aRemovalWhileOffIsNotShared() throws {
        let item = InMemorySecureDataItem()
        let deviceA = try SyncDevice(item: item, accounts: [fakeAccount("user-y")])
        let deviceD = try SyncDevice(item: item, accounts: [fakeAccount("user-y"), fakeAccount("user-d")])
        try deviceA.switchOn(at: 100)
        try deviceD.remove("user-y", at: 110)
        try deviceD.switchOn(at: 120)
        #expect(item.sharedPseudos == ["user-d", "user-y"])
        #expect(deviceD.pseudos == ["user-d", "user-y"])
    }
}
