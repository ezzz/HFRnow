import Foundation
import HFRModels
import Synchronization

/// A change of the device-only accounts, reported to the sync after the store accepted it.
public enum AccountSyncChange: Sendable, Hashable {
    /// An explicit login or re-login: new credentials and a new consent to share the account.
    case login(pseudo: String)
    /// Cookies, token or avatar refreshed without a login.
    case refresh(pseudo: String)
    /// The account was removed from this device.
    case removal(pseudo: String)
}

/// Why the sync switched this device off by itself.
public enum AccountSyncSwitchOff: Sendable, Hashable {
    /// Another device switched sharing off (a tombstone not earlier than this device's switch-on).
    case tombstone
    /// Another device switched on after an opt-out this device may have missed: it must be switched on again by hand.
    case laterSwitchOn
}

/// What one sync operation did to this device.
public struct AccountSyncReport: Sendable, Hashable {
    /// Pseudos added to this device or whose stored credentials were replaced by another device's.
    public var replaced: Set<String> = []
    /// Pseudos removed from this device.
    public var dropped: Set<String> = []
    /// Set when the device switched itself off.
    public var switchedOff: AccountSyncSwitchOff?
    /// True when the accounts were imported from the synchronizable copy (first launch on a new device).
    public var bootstrapped = false
    /// True when the synchronizable item was written.
    public var itemWritten = false

    /// An empty report.
    public init() {}
}

/// Why a sync operation could not run.
public enum AccountSyncError: Error, Sendable, Hashable {
    /// Another device kept changing the synchronizable item between this device's read and its write.
    case itemChanged
}

/// The opt-in iCloud Keychain sync of the accounts (ADR 0013 §6, LOT-173): the device-only store stays the master, a
/// synchronizable item carries a copy, and a device-only state item remembers the switch. Every operation runs under this
/// instance's lock; the app keeps one instance. Nothing here logs.
public final class AccountSync: Sendable {
    private let accounts: any CredentialStore
    private let item: any SecureDataItem
    private let stateItem: any SecureDataItem
    private let clock: @Sendable () -> Date
    private let lock = Mutex(())

    /// Smallest step above a known date for a new `enabledAt` (ADR: "strictly later").
    static let step: TimeInterval = 0.001
    /// How many times an explicit switch-on re-reads an item another device keeps changing.
    static let attempts = 3

    /// Creates the sync over the device-only `accounts`, the synchronizable `item` and this device's `state` item.
    public init(
        accounts: any CredentialStore, item: any SecureDataItem, state: any SecureDataItem,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.accounts = accounts
        self.item = item
        stateItem = state
        self.clock = clock
    }

    /// The device's state (off with nothing known when its item is absent or undecodable).
    public func state() throws -> AccountSyncState {
        try lock.withLock { _ in try loadState() }
    }

    /// Applies the rules of the reconcile table, at launch and at each foreground; such a read can confirm a provisional
    /// bootstrap.
    public func reconcile() throws -> AccountSyncReport {
        try lock.withLock { _ in try reconcileLocked(confirming: true) }
    }

    /// Records a change of the device-only accounts, then reconciles when the switch is on.
    public func localChange(_ change: AccountSyncChange) throws -> AccountSyncReport {
        try lock.withLock { _ in
            var state = try loadState()
            let now = clock()
            // Any change of the device-only accounts means this device held some: never a bootstrap source again.
            state.hadLocalAccounts = true
            switch change {
            case .login(let pseudo):
                let key = AccountKey.make(pseudo)
                state.stamps[key] = AccountStamp(credentialsAt: now, consentAt: now)
                // Entered on this device: never dropped by a provisional switch-off (spec D8); the other imported
                // accounts stay lent until the confirming read.
                state.imported.remove(key)
            case .refresh(let pseudo):
                let key = AccountKey.make(pseudo)
                state.stamps[key] = AccountStamp(credentialsAt: now, consentAt: state.stamps[key]?.consentAt ?? .distantPast)
            case .removal(let pseudo):
                let key = AccountKey.make(pseudo)
                state.stamps[key] = nil
                state.imported.remove(key)
                if state.isOn { state.removed[key] = now }
            }
            try saveState(state)
            // The push of a local change is not a confirming read: the provisional window lasts until the next launch or
            // foreground (ADR 0013 §6 *Bootstrap*).
            return state.isOn ? try reconcileLocked(confirming: false) : AccountSyncReport()
        }
    }

    /// The user's switch-on: refused when the item is unreadable; adopts and merges a live envelope, else starts a new one.
    public func switchOn() throws -> AccountSyncReport {
        try lock.withLock { _ in
            for _ in 0..<Self.attempts {
                if let report = try attemptSwitchOn() { return report }
            }
            throw AccountSyncError.itemChanged
        }
    }

    /// The user's switch-off: writes a tombstone over whatever the item holds and keeps the accounts entered here.
    public func switchOff() throws -> AccountSyncReport {
        try lock.withLock { _ in
            var state = try loadState()
            try noteLocalAccounts(&state)
            guard state.isOn, let enabledAt = state.enabledAt else { return AccountSyncReport() }
            let deletedAt = max(clock(), enabledAt)
            try item.write(AccountSyncEnvelope.tombstone(deletedAt: deletedAt).encoded())
            var report = try switchOffLocally(&state, honouring: deletedAt, reason: nil)
            report.itemWritten = true
            return report
        }
    }
}

// MARK: - Rules

extension AccountSync {
    private func reconcileLocked(confirming: Bool) throws -> AccountSyncReport {
        var state = try loadState()
        try noteLocalAccounts(&state)
        guard let raw = try item.read() else { return AccountSyncReport() }
        let envelope = try AccountSyncEnvelope.decode(raw)
        if state.isOn, let enabledAt = state.enabledAt {
            return try reconcileOn(&state, enabledAt: enabledAt, raw: raw, envelope: envelope, confirming: confirming)
        }
        return try reconcileOff(&state, raw: raw, envelope: envelope)
    }

    private func reconcileOn(
        _ state: inout AccountSyncState, enabledAt: Date, raw: Data, envelope: AccountSyncEnvelope, confirming: Bool
    ) throws -> AccountSyncReport {
        switch envelope {
        case .tombstone(let deletedAt):
            // A tie fails closed; an earlier tombstone is an opt-out this device's explicit switch-on superseded.
            if deletedAt >= enabledAt { return try switchOffLocally(&state, honouring: deletedAt, reason: .tombstone) }
            return try rewriteOwnEnvelope(state, enabledAt: enabledAt, over: raw)
        case .full(let other, let remote, let remoteRemoved):
            if other > enabledAt { return try switchOffLocally(&state, honouring: nil, reason: .laterSwitchOn) }
            // A raced or stale envelope: never lower the item's `enabledAt`, write this device's own over it.
            if other < enabledAt { return try rewriteOwnEnvelope(state, enabledAt: enabledAt, over: raw) }
            if confirming, state.provisionalEnabledAt == enabledAt {
                // The confirming read: the envelope this device bootstrapped from is still there.
                state.provisionalEnabledAt = nil
                state.imported = []
            }
            return try merge(&state, with: (remote, remoteRemoved), over: raw)
        }
    }

    private func rewriteOwnEnvelope(_ state: AccountSyncState, enabledAt: Date, over raw: Data) throws -> AccountSyncReport {
        var report = AccountSyncReport()
        let own = AccountSyncEnvelope.full(
            enabledAt: enabledAt, accounts: AccountSyncMerge.entries(of: try accounts.load(), stamps: state.stamps), removed: state.removed
        )
        report.itemWritten = try write(own, ifStill: raw)
        return report
    }

    private func reconcileOff(_ state: inout AccountSyncState, raw: Data, envelope: AccountSyncEnvelope) throws -> AccountSyncReport {
        var report = AccountSyncReport()
        switch envelope {
        case .full(let enabledAt, _, _) where state.honouredDeletedAt.map({ enabledAt <= $0 }) ?? false:
            // Race repair: a stale envelope written over a tombstone this device honoured.
            let honoured = state.honouredDeletedAt ?? enabledAt
            report.itemWritten = try write(.tombstone(deletedAt: honoured), ifStill: raw)
        case .full(let enabledAt, let remote, let removed) where !remote.isEmpty:
            // Only a new device: one that held accounts (logged out of all of them, or switched off) is never opted in
            // by itself (ADR 0013 §6 *Bootstrap*: "no device-only item").
            guard !state.hadLocalAccounts, try accounts.load().accounts.isEmpty else { break }
            report = try bootstrap(&state, enabledAt: enabledAt, remote: remote, removed: removed)
        case .tombstone(let deletedAt):
            guard try accounts.load().accounts.isEmpty, state.honouredDeletedAt.map({ $0 < deletedAt }) ?? true else { break }
            state.honouredDeletedAt = deletedAt
            try saveState(state)
        case .full:
            break
        }
        return report
    }

    private func bootstrap(
        _ state: inout AccountSyncState, enabledAt: Date, remote: [SyncedAccount], removed: [String: Date]
    ) throws -> AccountSyncReport {
        let book = AccountBook(accounts: remote.map(\.account))
        let keys = Set(book.accounts.map { AccountKey.make($0.pseudo) })
        // State first: a crash before the accounts are written leaves an "on" device that merges them at the next read.
        state.isOn = true
        state.hadLocalAccounts = true
        state.enabledAt = enabledAt
        state.provisionalEnabledAt = enabledAt
        state.imported = keys
        state.stamps = Dictionary(remote.map { (AccountKey.make($0.account.pseudo), $0.stamp) }) { first, _ in first }
        state.removed = removed
        try saveState(state)
        let written = try accounts.update { stored -> Bool in
            // An account entered meanwhile: the device is not new any more, nothing is imported.
            guard stored.accounts.isEmpty else { return false }
            stored = book
            return true
        }
        guard written else {
            state = AccountSyncState(honouredDeletedAt: state.honouredDeletedAt)
            state.hadLocalAccounts = true
            try saveState(state)
            return AccountSyncReport()
        }
        var report = AccountSyncReport()
        report.bootstrapped = true
        report.replaced = Set(book.accounts.map(\.pseudo))
        return report
    }

    private func attemptSwitchOn() throws -> AccountSyncReport? {
        var state = try loadState()
        try noteLocalAccounts(&state)
        guard !state.isOn else { return AccountSyncReport() }
        let raw = try item.read()
        let envelope = try raw.map(AccountSyncEnvelope.decode)
        let now = clock()
        if case .full(let enabledAt, let remote, let removed) = envelope,
           state.honouredDeletedAt.map({ enabledAt > $0 }) ?? true {
            state.isOn = true
            state.enabledAt = enabledAt
            state.removed = [:]
            let report = try merge(&state, with: (remote, removed), over: raw, required: true)
            return report.itemWritten ? report : nil
        }
        // Absent, a tombstone, or a raced envelope no later than a tombstone this device honoured: a new version.
        let floor = [envelope?.deletedAt, envelope?.enabledAt, state.honouredDeletedAt].compactMap { $0 }.max()
        let enabledAt = floor.map { max(now, $0.addingTimeInterval(Self.step)) } ?? now
        let own = AccountSyncEnvelope.full(
            enabledAt: enabledAt, accounts: AccountSyncMerge.entries(of: try accounts.load(), stamps: state.stamps), removed: [:]
        )
        guard try write(own, ifStill: raw) else { return nil }
        state.isOn = true
        state.enabledAt = enabledAt
        state.removed = [:]
        state.provisionalEnabledAt = nil
        state.imported = []
        try saveState(state)
        var report = AccountSyncReport()
        report.itemWritten = true
        return report
    }

    /// Merges the device-only accounts with a live envelope of the state's `enabledAt` and writes each side that changed.
    /// With `required` (a switch-on), the item is written even when the merge changes nothing in it, so the switch-on is
    /// confirmed by a write that saw the same bytes; the state is saved only once the item was written.
    private func merge(
        _ state: inout AccountSyncState, with remote: (accounts: [SyncedAccount], removed: [String: Date]), over raw: Data?,
        required: Bool = false
    ) throws -> AccountSyncReport {
        guard let enabledAt = state.enabledAt else { return AccountSyncReport() }
        let snapshot = state
        let mergeLocal: (AccountBook) -> AccountSyncMerge = { book in
            AccountSyncMerge(
                local: book, stamps: snapshot.stamps, localRemoved: snapshot.removed, remote: remote.accounts, remoteRemoved: remote.removed
            )
        }
        // The item first, the device-only store only once the item holds the merge (or needed no write): a failed or raced
        // write never leaves another device's accounts on this one.
        let preview = mergeLocal(try accounts.load())
        let merged = AccountSyncEnvelope.full(enabledAt: enabledAt, accounts: preview.entries, removed: preview.removed)
        var report = AccountSyncReport()
        let unchanged = (try? raw.map(AccountSyncEnvelope.decode)) == .some(merged)
        if required || !unchanged {
            report.itemWritten = try write(merged, ifStill: raw)
            guard report.itemWritten else { return report }
        }
        let result = try accounts.update { book -> AccountSyncMerge in
            let result = mergeLocal(book)
            book = result.book
            return result
        }
        state.stamps = result.stamps
        state.removed = result.removed
        state.imported.formIntersection(result.stamps.keys)
        report.replaced = result.replaced
        report.dropped = result.dropped
        try saveState(state)
        return report
    }

    /// Switches this device off without writing the item; a provisional bootstrap drops the accounts it imported.
    private func switchOffLocally(
        _ state: inout AccountSyncState, honouring deletedAt: Date?, reason: AccountSyncSwitchOff?
    ) throws -> AccountSyncReport {
        var report = AccountSyncReport()
        report.switchedOff = reason
        if state.isProvisional, !state.imported.isEmpty {
            let imported = state.imported
            report.dropped = try accounts.update { book -> Set<String> in
                let lent = book.accounts.filter { imported.contains(AccountKey.make($0.pseudo)) }.map(\.pseudo)
                for pseudo in lent { book.remove(pseudo: pseudo) }
                return Set(lent)
            }
        }
        let honoured = [state.honouredDeletedAt, deletedAt].compactMap { $0 }.max()
        var off = AccountSyncState(honouredDeletedAt: honoured)
        off.hadLocalAccounts = state.hadLocalAccounts
        off.stamps = state.stamps.filter { !report.dropped.map(AccountKey.make).contains($0.key) }
        state = off
        try saveState(state)
        return report
    }

    /// Writes `envelope` if the item still holds `expected`; false when another device wrote meanwhile (the next
    /// reconcile decides again).
    private func write(_ envelope: AccountSyncEnvelope, ifStill expected: Data?) throws -> Bool {
        guard try item.read() == expected else { return false }
        try item.write(envelope.encoded())
        return true
    }

    /// The state; off with nothing known when the item is absent or undecodable. A Keychain refusal (device locked before
    /// its first unlock) throws: read as "off", the next save would erase the switch and the tombstones it honoured.
    private func loadState() throws -> AccountSyncState {
        AccountSyncState.decoded(from: try stateItem.read())
    }

    /// Remembers, once, that this device holds accounts of its own: it is not a new device any more.
    private func noteLocalAccounts(_ state: inout AccountSyncState) throws {
        guard !state.hadLocalAccounts, try !accounts.load().accounts.isEmpty else { return }
        state.hadLocalAccounts = true
        try saveState(state)
    }

    private func saveState(_ state: AccountSyncState) throws {
        try stateItem.write(state.encoded())
    }
}

extension AccountSyncState {
    /// An "off" state that remembers the newest tombstone it honoured.
    init(honouredDeletedAt: Date?) {
        self.init()
        self.honouredDeletedAt = honouredDeletedAt
    }
}
