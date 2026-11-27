import Foundation
import HFRModels
import Testing
@testable import HFRStorage

/// An account with fake login cookies (`md_user`, `md_passs`, `md_id`) expiring at `expires`, as HFR sets them (+30 days,
/// HFR-PROTOCOL §5 `W03`), and the non-secret `p=1` a list page adds.
private func expiringAccount(_ pseudo: String, cookie: String = "fake-1", id: String = "fake-id", expires: Date) -> Account {
    Account(pseudo: pseudo, cookies: [
        StoredCookie(name: "md_user", value: pseudo, domain: ".hardware.fr", expiresDate: expires),
        StoredCookie(name: "md_passs", value: cookie, domain: ".hardware.fr", expiresDate: expires),
        StoredCookie(name: "md_id", value: id, domain: ".hardware.fr", expiresDate: expires)
    ], hashCheck: "fake-hash")
}

extension SyncDevice {
    /// A valid session check: HFR re-sent the same login cookies with a later expiry (`R74`), the app wrote them back and
    /// reported a refresh (`AccountsModel.persistSession`).
    @discardableResult
    func renewExpiries(
        _ pseudo: String, cookie: String = "fake-1", id: String = "fake-id", expires: Date, at time: TimeInterval
    ) throws -> AccountSyncReport {
        clock.set(time)
        try accounts.update { book in
            guard var account = book.account(matching: pseudo) else { return }
            account.cookies = expiringAccount(pseudo, cookie: cookie, id: id, expires: expires).cookies
            book.replace(account)
        }
        return try sync.localChange(.refresh(pseudo: pseudo))
    }

    /// The stored expiry of an account's `md_user`.
    func expiry(of pseudo: String) -> Date? {
        (try? accounts.load().account(matching: pseudo))?.cookies.first { $0.name == "md_user" }?.expiresDate
    }
}

/// #1390 (audit #1388 A1): a refresh that only renewed the cookies' expiry dates is not new credentials.
@Suite struct AccountSyncExpiryRefreshTests {
    /// Two devices sharing `x`, the second one bootstrapped from the first.
    private func sharedPair(_ item: InMemorySecureDataItem) throws -> (SyncDevice, SyncDevice) {
        let deviceA = try SyncDevice(item: item, accounts: [expiringAccount("x", expires: moment(1_000))])
        try deviceA.switchOn(at: 100)
        let deviceB = try SyncDevice(item: item)
        let boot = try deviceB.reconcile(at: 110)
        #expect(boot.bootstrapped)
        try deviceB.reconcile(at: 120)
        return (deviceA, deviceB)
    }

    // The issue's count: one valid check = one write of the synchronizable item, and one `replaced` on the other device.
    @Test func anExpiryOnlyRefreshWritesNothingAndIsNotReplacedElsewhere() throws {
        let item = InMemorySecureDataItem()
        let (deviceA, deviceB) = try sharedPair(item)
        let before = item.data
        let writes = item.writeCount
        let report = try deviceA.renewExpiries("x", expires: moment(5_000), at: 200)
        #expect(!report.itemWritten, "an expiry-only refresh rewrote the synchronizable item")
        #expect(item.writeCount == writes)
        #expect(item.data == before)
        #expect(report.replaced.isEmpty)
        #expect(deviceA.expiry(of: "x") == moment(5_000), "the device lost its own renewed expiry")
        let echo = try deviceB.reconcile(at: 210)
        #expect(echo.replaced.isEmpty, "the other device reported an expiry-only refresh as new credentials")
        #expect(!echo.itemWritten)
    }

    // Repeated checks on both devices: none of them writes the item (the launch loop of #1276 needs one write each).
    @Test func repeatedChecksOnBothDevicesNeverWrite() throws {
        let item = InMemorySecureDataItem()
        let (deviceA, deviceB) = try sharedPair(item)
        let writes = item.writeCount
        for step in 1...5 {
            let time = TimeInterval(200 + step * 10)
            #expect(try !deviceA.renewExpiries("x", expires: moment(5_000 + time), at: time).itemWritten)
            #expect(try deviceB.reconcile(at: time + 1).replaced.isEmpty)
            #expect(try !deviceB.renewExpiries("x", expires: moment(6_000 + time), at: time + 2).itemWritten)
            #expect(try deviceA.reconcile(at: time + 3).replaced.isEmpty)
        }
        #expect(item.writeCount == writes)
    }

    // Comment 7221677106 (b): a copy dated ahead of this device's clock no longer freezes this device's expiries.
    @Test func aCopyDatedAheadKeepsThisDevicesLaterExpiries() throws {
        let item = InMemorySecureDataItem()
        let (deviceA, deviceB) = try sharedPair(item)
        // B's clock is far ahead: its re-login of the same credentials dates the copy after anything A can stamp.
        clockAheadLogin(deviceB, cookie: "fake-1", expires: moment(1_500), at: 10_000)
        try deviceA.reconcile(at: 150)
        let report = try deviceA.renewExpiries("x", expires: moment(9_000), at: 200)
        #expect(report.replaced.isEmpty)
        #expect(deviceA.expiry(of: "x") == moment(9_000), "the copy's older expiry replaced the device's renewed one")
        try deviceA.reconcile(at: 210)
        #expect(deviceA.expiry(of: "x") == moment(9_000))
    }

    // Acceptance: a re-login on one device is still adopted, once, by the other.
    @Test func aReLoginIsStillAdoptedOnce() throws {
        let item = InMemorySecureDataItem()
        let (deviceA, deviceB) = try sharedPair(item)
        try deviceA.renewExpiries("x", expires: moment(5_000), at: 200)
        let login = try deviceA.logIn("x", cookie: "fake-2", at: 300)
        #expect(login.itemWritten)
        let adopted = try deviceB.reconcile(at: 310)
        #expect(adopted.replaced == ["x"])
        #expect(deviceB.cookie(of: "x") == "fake-2")
        #expect(try deviceB.reconcile(at: 320).replaced.isEmpty, "the re-login was reported twice")
        #expect(try deviceA.reconcile(at: 330).replaced.isEmpty, "the re-login came back to its own device")
    }

    // A refresh that changed a login cookie's value (not only its date) is new credentials and still propagates.
    @Test func aRefreshWithANewLoginCookieStillPropagates() throws {
        let item = InMemorySecureDataItem()
        let (deviceA, deviceB) = try sharedPair(item)
        let report = try deviceA.renewExpiries("x", cookie: "fake-2", expires: moment(5_000), at: 200)
        #expect(report.itemWritten)
        #expect(try deviceB.reconcile(at: 210).replaced == ["x"])
        #expect(deviceB.cookie(of: "x") == "fake-2")
    }

    // Comment 7221677106 (a): a re-login on a device whose clock is behind the copy still wins.
    @Test func aReLoginWinsOverACopyDatedAhead() throws {
        let item = InMemorySecureDataItem()
        let (deviceA, deviceB) = try sharedPair(item)
        clockAheadLogin(deviceB, cookie: "fake-2", expires: moment(1_500), at: 10_000)
        #expect(try deviceA.reconcile(at: 150).replaced == ["x"])
        let login = try deviceA.logIn("x", cookie: "fake-3", at: 200)
        #expect(login.itemWritten)
        #expect(deviceA.cookie(of: "x") == "fake-3", "the copy dated ahead undid this device's re-login")
        #expect(try deviceB.reconcile(at: 10_010).replaced == ["x"])
        #expect(deviceB.cookie(of: "x") == "fake-3")
    }

    // A refresh with new login cookies on a device whose clock is behind the copy wins too.
    @Test func aNewLoginCookieWinsOverACopyDatedAhead() throws {
        let item = InMemorySecureDataItem()
        let (deviceA, deviceB) = try sharedPair(item)
        clockAheadLogin(deviceB, cookie: "fake-2", expires: moment(1_500), at: 10_000)
        try deviceA.reconcile(at: 150)
        try deviceA.renewExpiries("x", cookie: "fake-3", expires: moment(5_000), at: 200)
        #expect(deviceA.cookie(of: "x") == "fake-3")
        #expect(try deviceB.reconcile(at: 10_010).replaced == ["x"])
        #expect(deviceB.cookie(of: "x") == "fake-3")
    }

    // Round 1 finding 3c: `md_id` is part of the login.
    @Test func aRefreshWithANewProfileIDStillPropagates() throws {
        let item = InMemorySecureDataItem()
        let (deviceA, deviceB) = try sharedPair(item)
        #expect(try deviceA.renewExpiries("x", id: "fake-id-2", expires: moment(5_000), at: 200).itemWritten)
        #expect(try deviceB.reconcile(at: 210).replaced == ["x"])
    }

    // Round 1 finding 1: a copy whose expiries lag far behind takes the device's, once, so a new device never imports
    // cookies past their expiry.
    @Test func aCopyFarBehindTakesTheRenewedCookiesOnce() throws {
        let item = InMemorySecureDataItem()
        let (deviceA, deviceB) = try sharedPair(item)
        let renewed = moment(1_000 + AccountSyncMerge.renewalMargin + 1)
        let report = try deviceA.renewExpiries("x", expires: renewed, at: 200)
        #expect(report.itemWritten, "the copy kept cookies that lag past the margin")
        #expect(report.replaced.isEmpty)
        #expect(try deviceB.reconcile(at: 210).replaced.isEmpty, "a renewal was reported as new credentials")
        #expect(deviceB.expiry(of: "x") == moment(1_000), "the other device's own cookies were replaced")
        #expect(try !deviceA.renewExpiries("x", expires: renewed.addingTimeInterval(3_600), at: 220).itemWritten)
        #expect(try !deviceB.renewExpiries("x", expires: renewed.addingTimeInterval(7_200), at: 230).itemWritten)
        let deviceC = try SyncDevice(item: item)
        #expect(try deviceC.reconcile(at: 240).bootstrapped)
        #expect(deviceC.expiry(of: "x") == renewed, "a new device imported the first share's expiry")
    }

    // Round 1 finding 2: devices with different main accounts do not rewrite the copy at every check.
    @Test func differentMainAccountsDoNotRewriteTheCopy() throws {
        let item = InMemorySecureDataItem()
        let deviceA = try SyncDevice(item: item, accounts: [
            expiringAccount("x", expires: moment(1_000)), expiringAccount("y", expires: moment(1_000))
        ])
        try deviceA.switchOn(at: 100)
        let deviceB = try SyncDevice(item: item)
        try deviceB.reconcile(at: 110)
        try deviceB.reconcile(at: 120)
        #expect(try deviceB.accounts.setMain(pseudo: "y"))
        #expect(try deviceA.accounts.mainAccount()?.pseudo == "x")
        #expect(try deviceB.accounts.mainAccount()?.pseudo == "y")
        let writes = item.writeCount
        for step in 1...4 {
            let time = TimeInterval(200 + step * 10)
            for pseudo in ["x", "y"] {
                #expect(try !deviceA.renewExpiries(pseudo, expires: moment(2_000 + time), at: time).itemWritten)
                #expect(try !deviceB.renewExpiries(pseudo, expires: moment(3_000 + time), at: time + 1).itemWritten)
            }
            #expect(try deviceA.reconcile(at: time + 2).replaced.isEmpty)
            #expect(try deviceB.reconcile(at: time + 3).replaced.isEmpty)
        }
        #expect(item.writeCount == writes)
        #expect(try deviceA.accounts.mainAccount()?.pseudo == "x")
        #expect(try deviceB.accounts.mainAccount()?.pseudo == "y")
    }

    // Round 1 finding 3a: a re-login after a removal dated ahead brings the account back.
    @Test func aReLoginBeatsARemovalDatedAhead() throws {
        let item = InMemorySecureDataItem()
        let (deviceA, deviceB) = try sharedPair(item)
        try deviceB.remove("x", at: 10_000)
        #expect(try deviceA.reconcile(at: 150).dropped == ["x"])
        try deviceA.logIn("x", cookie: "fake-2", at: 200)
        #expect(deviceA.pseudos == ["x"], "the removal dated ahead beat a later explicit login")
        #expect(try deviceB.reconcile(at: 10_010).replaced == ["x"])
    }

    // Round 1 finding 3b: the floor reads the copy, not only this device's last reconcile.
    @Test func aReLoginWithoutAReconcileStillBeatsACopyDatedAhead() throws {
        let item = InMemorySecureDataItem()
        let (deviceA, deviceB) = try sharedPair(item)
        clockAheadLogin(deviceB, cookie: "fake-2", expires: moment(1_500), at: 10_000)
        try deviceA.logIn("x", cookie: "fake-3", at: 200)
        #expect(deviceA.cookie(of: "x") == "fake-3", "the copy dated ahead undid a re-login made before any reconcile")
        #expect(try deviceB.reconcile(at: 10_010).replaced == ["x"])
    }

    // Round 1 finding 4: a removal on a device whose clock is behind the copy's last login still wins.
    @Test func aRemovalBeatsALoginDatedAhead() throws {
        let item = InMemorySecureDataItem()
        let (deviceA, deviceB) = try sharedPair(item)
        clockAheadLogin(deviceB, cookie: "fake-1", expires: moment(1_500), at: 10_000)
        try deviceA.reconcile(at: 150)
        let removal = try deviceA.remove("x", at: 200)
        #expect(removal.replaced.isEmpty, "the removed account came back")
        #expect(deviceA.pseudos == [])
        #expect(try deviceB.reconcile(at: 10_010).dropped == ["x"])
    }

    private func clockAheadLogin(_ device: SyncDevice, cookie: String, expires: Date, at time: TimeInterval) {
        device.clock.set(time)
        #expect(throws: Never.self) {
            try device.accounts.save(expiringAccount("x", cookie: cookie, expires: expires), makeMain: false)
            try device.sync.localChange(.login(pseudo: "x"))
        }
    }
}
