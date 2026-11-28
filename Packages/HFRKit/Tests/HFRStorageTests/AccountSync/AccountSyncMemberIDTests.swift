import Foundation
import HFRModels
import Testing
@testable import HFRStorage

/// #1420: only a login sets `md_id` and HFR refuses profiles without it (`R1420c`). A newer copy of the same login from a
/// device that lacks it (a legacy import, a login past 30 days) must not take it from the device that holds it, in the store
/// nor in the shared copy; another login's copy is taken as it is.
@Suite struct AccountSyncMemberIDTests {
    let item = InMemorySecureDataItem()

    private static func memberID(_ value: String = "900001", expires: Date? = nil) -> StoredCookie {
        StoredCookie(name: "md_id", value: value, domain: ".hardware.fr", expiresDate: expires)
    }

    private static func withMemberID(_ pseudo: String) -> Account {
        var account = fakeAccount(pseudo)
        account.cookies.append(memberID())
        return account
    }

    private static func memberIDs(_ device: SyncDevice, _ pseudo: String) -> [String] {
        ((try? device.accounts.load().account(matching: pseudo))?.cookies ?? []).filter { $0.name == "md_id" }.map(\.value)
    }

    private func sharedMemberIDs(_ pseudo: String) throws -> [String] {
        guard case .full(_, let accounts, _)? = try item.envelope else { return [] }
        return accounts.first { $0.account.pseudo == pseudo }?.account.cookies.filter { $0.name == "md_id" }.map(\.value) ?? []
    }

    @Test func aNewerCopyOfTheSameLoginWithoutMemberIDKeepsThisDevicesAndConverges() throws {
        let deviceA = try SyncDevice(item: item, accounts: [Self.withMemberID("user-a")])
        try deviceA.switchOn(at: 100)
        let deviceB = try SyncDevice(item: item, accounts: [fakeAccount("user-a")])
        try deviceB.switchOn(at: 105)
        // B's check writes back its jar, without `md_id`, and pushes a refresh dated after A's copy.
        try deviceB.refresh("user-a", cookie: "fake-1", at: 110)
        try deviceA.reconcile(at: 120)
        #expect(Self.memberIDs(deviceA, "user-a") == ["900001"])
        #expect(try sharedMemberIDs("user-a") == ["900001"])
        try deviceB.reconcile(at: 130)
        #expect(Self.memberIDs(deviceB, "user-a") == ["900001"])
        // Converged: nothing left to write on either side.
        #expect(try deviceA.reconcile(at: 140).itemWritten == false)
        #expect(try deviceB.reconcile(at: 150).itemWritten == false)
    }

    /// A re-login on the other device (another `md_passs`) is another login: its copy wins as it is.
    @Test func anotherLoginsCopyIsTakenAsItIs() throws {
        let deviceA = try SyncDevice(item: item, accounts: [Self.withMemberID("user-a")])
        try deviceA.switchOn(at: 100)
        let deviceB = try SyncDevice(item: item)
        try deviceB.reconcile(at: 110)
        try deviceB.logIn("user-a", cookie: "fake-new", at: 120)
        try deviceA.reconcile(at: 130)
        #expect(deviceA.cookie(of: "user-a") == "fake-new")
        #expect(Self.memberIDs(deviceA, "user-a").isEmpty)
    }

    /// The winner's `md_id` counts only when live (`StoredCookie.isLiveMemberID`); the local one is kept only when live.
    @Test func onlyALiveMemberIDCounts() {
        let now = moment(1_000)
        let login = fakeAccount("user-a").cookies
        for dead in [Self.memberID("deleted"), Self.memberID(""), Self.memberID(expires: moment(999))] {
            let merged = AccountSyncMerge.cookies(login + [dead], keepingMemberIDOf: login + [Self.memberID()], now: now)
            #expect(merged.filter { $0.name == "md_id" }.map(\.value) == ["900001"])
            #expect(AccountSyncMerge.cookies(login, keepingMemberIDOf: login + [dead], now: now) == login)
        }
        let own = login + [Self.memberID("900009")]
        #expect(AccountSyncMerge.cookies(own, keepingMemberIDOf: login + [Self.memberID()], now: now) == own)
    }
}
