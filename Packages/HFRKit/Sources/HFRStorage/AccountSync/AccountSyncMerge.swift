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
            var account = kept.account
            if sameLogin, let localEntry, let remoteEntry {
                // The copy's main flag stays: devices with different main accounts would rewrite it at every merge.
                copyMain[key] = remoteEntry.account.isMain
                (kept.account, account) = Self.sameLoginAccounts(local: localEntry.account, copy: remoteEntry.account)
            }
            account.isMain = key == localMainKey
            merged.append(kept)
            deviceAccounts.append(account)
        }
        let book = AccountBook(accounts: deviceAccounts)
        self.book = book
        // When this device's main account is not a same-login entry, its own flag goes into the copy, the copy's ones go.
        let ownMain = book.main.map { copyMain[AccountKey.make($0.pseudo)] == nil } ?? false
        entries = merged.map { entry in
            var entry = entry
            let key = AccountKey.make(entry.account.pseudo)
            entry.account.isMain = (ownMain ? nil : copyMain[key]) ?? book.account(matching: entry.account.pseudo)?.isMain ?? false
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

    /// The copy's and this device's account for one login held on both sides. Each keeps its own, unless its cookies lag
    /// more than `renewalMargin` behind the other's: it then takes the other's, or it would keep (or a device bootstrapping
    /// from the copy would import) cookies past their expiry. One write or adoption per account and period, not per check.
    private static func sameLoginAccounts(local: Account, copy: Account) -> (copy: Account, device: Account) {
        let localExpiry = loginExpiry(of: local), copyExpiry = loginExpiry(of: copy)
        if localExpiry > copyExpiry.addingTimeInterval(renewalMargin) { return (local, local) }
        if copyExpiry > localExpiry.addingTimeInterval(renewalMargin) { return (copy, copy) }
        return (copy, local)
    }

    /// The latest expiry of an account's login cookies; `distantPast` when none has one.
    static func loginExpiry(of account: Account) -> Date {
        account.cookies.filter { loginCookies.contains($0.name) }.compactMap(\.expiresDate).max() ?? .distantPast
    }

    /// Whether two copies of an account hold the same login: the same values of the login cookies, dates ignored. `md_id`
    /// counts only when both hold it: `R74` renews `md_user` and `md_passs`, not `md_id`, which leaves a jar 30 days after
    /// the login (`W03`).
    static func sameLogin(_ first: Account, _ second: Account) -> Bool {
        var one = loginIdentity(of: first), other = loginIdentity(of: second)
        if one["md_id"] == nil || other["md_id"] == nil {
            one["md_id"] = nil
            other["md_id"] = nil
        }
        return one == other
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
