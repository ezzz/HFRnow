import Foundation
import HFRModels

/// The per-account merge of the device-only accounts and the synchronizable copy (LOT-173 spec, "Merge"): newest
/// credentials per account key, a removal marker beats every copy whose last explicit login is not later than it, the
/// device keeps its own main account. Pure.
struct AccountSyncMerge {
    /// The merged accounts, local order first, main flag of this device.
    var book: AccountBook
    /// The merged accounts with their dates, for the synchronizable copy.
    var entries: [SyncedAccount]
    /// Removal markers still standing.
    var removed: [String: Date]
    /// Dates of the merged accounts by account key.
    var stamps: [String: AccountStamp]
    /// Pseudos added on this device or whose stored copy changed.
    var replaced: Set<String>
    /// Pseudos this device stored and no longer does.
    var dropped: Set<String>

    /// Merges `local` (with this device's `stamps` and `localRemoved`) and the copy's `remote` accounts and markers.
    init(
        local: AccountBook, stamps localStamps: [String: AccountStamp], localRemoved: [String: Date],
        remote: [SyncedAccount], remoteRemoved: [String: Date]
    ) {
        var remoteByKey: [String: SyncedAccount] = [:]
        for entry in remote where remoteByKey[AccountKey.make(entry.account.pseudo)] == nil {
            remoteByKey[AccountKey.make(entry.account.pseudo)] = entry
        }
        var order: [String] = []
        for key in local.accounts.map({ AccountKey.make($0.pseudo) }) + remote.map({ AccountKey.make($0.account.pseudo) })
        where !order.contains(key) {
            order.append(key)
        }
        let localMainKey = local.main.map { AccountKey.make($0.pseudo) }
        var removed = localRemoved.merging(remoteRemoved) { max($0, $1) }
        var merged: [SyncedAccount] = []
        var deviceAccounts: [Account] = []
        var copyMain: [String: Bool] = [:]
        for key in order {
            let localEntry = local.accounts.first { AccountKey.make($0.pseudo) == key }
                .map { SyncedAccount(account: $0, stamp: localStamps[key] ?? .unknown) }
            let remoteEntry = remoteByKey[key]
            // Same login on both sides (#1390): only cookie dates or details can differ, which are not new credentials. The
            // copy keeps its entry and dates, so a renewed expiry neither rewrites the item at every check nor reads as
            // `replaced` on another device, and this device keeps its own account, with the expiries its jar renewed.
            let sameLogin = localEntry.map { local in remoteEntry.map { Self.sameLogin(local.account, $0.account) } ?? false } ?? false
            guard var kept = sameLogin ? remoteEntry : Self.newer(localEntry, remoteEntry) else { continue }
            kept.consentAt = max(localEntry?.consentAt ?? .distantPast, remoteEntry?.consentAt ?? .distantPast)
            if let removal = removed[key], removal >= kept.consentAt { continue }
            removed[key] = nil
            if sameLogin, let localEntry, let remoteEntry {
                // The copy's main flag stays: devices with different main accounts would rewrite it at every merge.
                copyMain[key] = remoteEntry.account.isMain
                // A copy whose cookies lag far behind this device's takes them, or a device bootstrapping from it would
                // import cookies past their expiry; the margin keeps it to one write per account and period, not per check.
                let lagging = Self.loginExpiry(of: remoteEntry.account).addingTimeInterval(Self.renewalMargin)
                if Self.loginExpiry(of: localEntry.account) > lagging { kept.account = localEntry.account }
            }
            var account = sameLogin ? localEntry?.account ?? kept.account : kept.account
            account.isMain = key == localMainKey
            merged.append(kept)
            deviceAccounts.append(account)
        }
        let book = AccountBook(accounts: deviceAccounts)
        self.book = book
        entries = merged.map { entry in
            var entry = entry
            let key = AccountKey.make(entry.account.pseudo)
            entry.account.isMain = copyMain[key] ?? book.account(matching: entry.account.pseudo)?.isMain ?? false
            return entry
        }
        self.removed = removed
        stamps = Dictionary(merged.map { (AccountKey.make($0.account.pseudo), $0.stamp) }) { first, _ in first }
        let before = Dictionary(local.accounts.map { ($0.pseudo, $0) }) { first, _ in first }
        replaced = Set(book.accounts.filter { account in
            guard var old = before[account.pseudo] else { return true }
            old.isMain = account.isMain
            return old != account
        }.map(\.pseudo))
        dropped = Set(local.accounts.map(\.pseudo)).subtracting(book.accounts.map(\.pseudo))
    }

    /// The copy with the later `credentialsAt`; a tie keeps the remote one, so every device converges on the same bytes.
    private static func newer(_ local: SyncedAccount?, _ remote: SyncedAccount?) -> SyncedAccount? {
        guard let local else { return remote }
        guard let remote else { return local }
        return local.credentialsAt > remote.credentialsAt ? local : remote
    }

    /// The cookies that make a login (HFR-PROTOCOL §5, `W03`); HFR re-sends `md_user` and `md_passs` with a new expiry on
    /// every logged-in answer (`R74`), and other cookies (`p`, `md_data`) come and go without a login.
    static let loginCookies = ["md_user", "md_passs", "md_id"]

    /// How far ahead of the copy's a device's login-cookie expiry must be for a same-login merge to share it (#1390). HFR
    /// renews the expiry to +30 days on every logged-in answer (`W03`, `R74`): the copy then stays valid for 23 days at
    /// least, for at most one write per account and week instead of one per session check.
    static let renewalMargin: TimeInterval = 7 * 24 * 3_600

    /// The latest expiry of an account's login cookies; `distantPast` when none has one.
    static func loginExpiry(of account: Account) -> Date {
        account.cookies.filter { loginCookies.contains($0.name) }.compactMap(\.expiresDate).max() ?? .distantPast
    }

    /// Whether two copies of an account hold the same login: the same values of the login cookies, dates ignored.
    static func sameLogin(_ first: Account, _ second: Account) -> Bool {
        loginIdentity(of: first) == loginIdentity(of: second)
    }

    private static func loginIdentity(of account: Account) -> [String: [String]] {
        var identity: [String: [String]] = [:]
        for cookie in account.cookies where loginCookies.contains(cookie.name) {
            identity[cookie.name, default: []].append(cookie.value)
        }
        return identity.mapValues { $0.sorted() }
    }

    /// The entries of `book` with this device's dates, for writing its own full envelope.
    static func entries(of book: AccountBook, stamps: [String: AccountStamp]) -> [SyncedAccount] {
        book.accounts.map { SyncedAccount(account: $0, stamp: stamps[AccountKey.make($0.pseudo)] ?? .unknown) }
    }
}
