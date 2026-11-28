import Foundation
import HFRModels

/// The per-account merge of the device-only accounts and the synchronizable copy (LOT-173 spec, "Merge"): newest
/// credentials per account key, a removal marker beats every copy whose last explicit login is not later than it, the
/// device keeps its own main account; a winning copy of the same login without `md_id` keeps this device's (#1420). Pure.
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

    /// Merges `local` (with this device's `stamps` and `localRemoved`) and the copy's `remote` accounts and markers; `now` dates
    /// the `md_id` kept from `local` (#1420).
    init(
        local: AccountBook, stamps localStamps: [String: AccountStamp], localRemoved: [String: Date],
        remote: [SyncedAccount], remoteRemoved: [String: Date], now: Date = Date()
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
        for key in order {
            let localEntry = local.accounts.first { AccountKey.make($0.pseudo) == key }
                .map { SyncedAccount(account: $0, stamp: localStamps[key] ?? .unknown) }
            guard var kept = Self.newer(localEntry, remoteByKey[key]) else { continue }
            kept.account.cookies = Self.cookies(kept.account.cookies, keepingMemberIDOf: localEntry?.account.cookies ?? [], now: now)
            kept.consentAt = max(localEntry?.consentAt ?? .distantPast, remoteByKey[key]?.consentAt ?? .distantPast)
            if let removal = removed[key], removal >= kept.consentAt { continue }
            removed[key] = nil
            kept.account.isMain = key == localMainKey
            merged.append(kept)
        }
        let book = AccountBook(accounts: merged.map(\.account))
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

    /// `winner` with `local`'s live `md_id` when `winner` holds none and both are the same login (same `md_user` and
    /// `md_passs`, #1385's identity): only a login sets `md_id` and HFR refuses profiles without it (`R1420c`), so a newer copy
    /// from a device that lacks it (a legacy import, a login past 30 days) must not take it from this one (#1420). The merged
    /// entry carries it, so every device converges on the copy with it; another login's copy is taken as it is.
    static func cookies(_ winner: [StoredCookie], keepingMemberIDOf local: [StoredCookie], now: Date) -> [StoredCookie] {
        guard !winner.contains(where: { $0.isLiveMemberID(at: now) }) else { return winner }
        let kept = local.filter { $0.isLiveMemberID(at: now) }
        let identity = { (cookies: [StoredCookie]) in
            Set(cookies.filter { ["md_user", "md_passs"].contains($0.name) }.map { "\($0.name)=\($0.value)" })
        }
        let login = identity(local)
        guard !kept.isEmpty, login.contains(where: { $0.hasPrefix("md_user=") }), !login.contains("md_user=deleted"),
            login == identity(winner)
        else { return winner }
        return winner.filter { $0.name != StoredCookie.memberIDName } + kept
    }

    /// The entries of `book` with this device's dates, for writing its own full envelope.
    static func entries(of book: AccountBook, stamps: [String: AccountStamp]) -> [SyncedAccount] {
        book.accounts.map { SyncedAccount(account: $0, stamp: stamps[AccountKey.make($0.pseudo)] ?? .unknown) }
    }
}
