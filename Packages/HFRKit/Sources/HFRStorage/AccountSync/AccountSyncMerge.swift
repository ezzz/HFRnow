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
        for key in order {
            let localEntry = local.accounts.first { AccountKey.make($0.pseudo) == key }
                .map { SyncedAccount(account: $0, stamp: localStamps[key] ?? .unknown) }
            let remoteEntry = remoteByKey[key]
            // Same login on both sides (#1390): only cookie dates or details can differ, which are not new credentials. The
            // copy keeps its entry, so a renewed expiry never rewrites the item nor reads as `replaced` on another device,
            // and this device keeps its own account, with the expiries its jar renewed, whatever the stamps say.
            let sameLogin = localEntry.map { local in remoteEntry.map { Self.sameLogin(local.account, $0.account) } ?? false } ?? false
            guard var kept = sameLogin ? remoteEntry : Self.newer(localEntry, remoteEntry) else { continue }
            kept.consentAt = max(localEntry?.consentAt ?? .distantPast, remoteEntry?.consentAt ?? .distantPast)
            if let removal = removed[key], removal >= kept.consentAt { continue }
            removed[key] = nil
            kept.account.isMain = key == localMainKey
            var account = sameLogin ? localEntry?.account ?? kept.account : kept.account
            account.isMain = kept.account.isMain
            merged.append(kept)
            deviceAccounts.append(account)
        }
        let book = AccountBook(accounts: deviceAccounts)
        self.book = book
        entries = merged.map { entry in
            var entry = entry
            entry.account.isMain = book.account(matching: entry.account.pseudo)?.isMain ?? false
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
