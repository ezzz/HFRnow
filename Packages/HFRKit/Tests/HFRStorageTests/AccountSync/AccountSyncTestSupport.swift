import Foundation
import HFRModels
import Synchronization
@testable import HFRStorage

/// A clock the test moves by hand.
final class SyncTestClock: Sendable {
    private let current: Mutex<Date>

    init(_ seconds: TimeInterval = 0) {
        current = Mutex(Date(timeIntervalSinceReferenceDate: seconds))
    }

    var now: Date { current.withLock { $0 } }

    func set(_ seconds: TimeInterval) {
        current.withLock { $0 = Date(timeIntervalSinceReferenceDate: seconds) }
    }
}

/// The date `seconds` after the reference date, as the tests write them (`moment(150)`).
func moment(_ seconds: TimeInterval) -> Date {
    Date(timeIntervalSinceReferenceDate: seconds)
}

/// An account with fake cookies naming it, so `AccountBook.add` accepts it.
func fakeAccount(_ pseudo: String, cookie: String = "fake-1") -> Account {
    Account(pseudo: pseudo, cookies: [
        StoredCookie(name: "md_user", value: pseudo, domain: ".hardware.fr"),
        StoredCookie(name: "md_passs", value: cookie, domain: ".hardware.fr")
    ], hashCheck: "fake-hash")
}

/// One simulated device: its own device-only accounts, its own state item and clock, and the synchronizable item shared
/// with the other devices of the same Apple ID.
struct SyncDevice {
    let accounts: InMemoryCredentialStore
    let state: InMemorySecureDataItem
    let clock: SyncTestClock
    let sync: AccountSync

    init(item: InMemorySecureDataItem, accounts: [Account] = []) throws {
        self.accounts = try InMemoryCredentialStore(accounts: accounts)
        if accounts.isEmpty { self.accounts.envelope = nil }
        state = InMemorySecureDataItem()
        let clock = SyncTestClock()
        self.clock = clock
        sync = AccountSync(accounts: self.accounts, item: item, state: state, clock: { clock.now })
    }

    /// Logs in (or again) at `time` and reports it.
    @discardableResult
    func logIn(_ pseudo: String, cookie: String = "fake-1", at time: TimeInterval) throws -> AccountSyncReport {
        clock.set(time)
        try accounts.save(fakeAccount(pseudo, cookie: cookie), makeMain: false)
        return try sync.localChange(.login(pseudo: pseudo))
    }

    /// Writes refreshed cookies at `time` and reports it.
    @discardableResult
    func refresh(_ pseudo: String, cookie: String, at time: TimeInterval) throws -> AccountSyncReport {
        clock.set(time)
        try accounts.update { book in
            guard var account = book.account(matching: pseudo) else { return }
            account.cookies = fakeAccount(pseudo, cookie: cookie).cookies
            book.replace(account)
        }
        return try sync.localChange(.refresh(pseudo: pseudo))
    }

    /// Removes an account at `time` and reports it.
    @discardableResult
    func remove(_ pseudo: String, at time: TimeInterval) throws -> AccountSyncReport {
        clock.set(time)
        try accounts.deleteAccount(pseudo: pseudo)
        return try sync.localChange(.removal(pseudo: pseudo))
    }

    @discardableResult
    func switchOn(at time: TimeInterval) throws -> AccountSyncReport {
        clock.set(time)
        return try sync.switchOn()
    }

    @discardableResult
    func switchOff(at time: TimeInterval) throws -> AccountSyncReport {
        clock.set(time)
        return try sync.switchOff()
    }

    @discardableResult
    func reconcile(at time: TimeInterval) throws -> AccountSyncReport {
        clock.set(time)
        return try sync.reconcile()
    }

    /// Stored pseudos, in order.
    var pseudos: [String] { (try? accounts.accounts().map(\.pseudo)) ?? [] }

    /// The stored `md_passs` value of an account.
    func cookie(of pseudo: String) -> String? {
        (try? accounts.load().account(matching: pseudo))?.cookies.first { $0.name == "md_passs" }?.value
    }

    var isOn: Bool { (try? sync.state())?.isOn ?? false }
}

extension InMemorySecureDataItem {
    /// The decoded envelope, nil when absent.
    var envelope: AccountSyncEnvelope? {
        get throws { try data.map(AccountSyncEnvelope.decode) }
    }

    /// Pseudos of a full envelope, sorted.
    var sharedPseudos: [String] {
        guard case .full(_, let accounts, _)? = try? envelope else { return [] }
        return accounts.map(\.account.pseudo).sorted()
    }
}
