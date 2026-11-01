import Foundation

/// The notification ledger of each HFR account, on this device only (LOT-091, ADR 0013: notifications are per device).
///
/// A background check reads `ledger(for:)` to know whether it is due and what is new (`NotificationLedger.diff`),
/// notifies, then records what it notified; the app records what it showed too, so a count seen in the app is not
/// notified later (legacy reset `nb_mp` from the tab badge, `HFRplusAppDelegate.m:706`). Ledgers are keyed by account
/// key (ADR 0013 §7), so `Alice` and `alice` share one; removing an account drops its ledger.
public actor NotificationLedgerStore {
    private var state: SmallStoreState<NotificationLedgerDocument>

    /// Creates a store over `persistence`; nothing is read until the first call.
    public init(persistence: any SmallStorePersistence<NotificationLedgerDocument>) {
        state = SmallStoreState(persistence: persistence)
    }

    // MARK: Reading

    /// The account's ledger; an empty one when none is stored or the stored data is unreadable.
    public func ledger(for account: String) -> NotificationLedger {
        state.document()?.accounts[AccountKey.make(account)] ?? NotificationLedger()
    }

    /// The reason writes are refused, or nil when the store is usable (loading it if needed).
    public func loadFailure() -> SmallStoreError? {
        state.failure()
    }

    // MARK: Writing

    /// Records `summary` as notified for the account (`NotificationLedger.record`). Returns false when nothing changed.
    @discardableResult
    public func record(_ summary: NotificationSummary, account: String) throws(SmallStoreError) -> Bool {
        if let reason = summary.invalidReason { throw .invalidValue(reason: reason) }
        return try update(account) { ledger in ledger.record(summary) }
    }

    /// Records a check of the account at `date` (`NotificationLedger.markChecked`). Returns false when nothing changed.
    @discardableResult
    public func markChecked(account: String, at date: Date = .now) throws(SmallStoreError) -> Bool {
        try update(account) { ledger in ledger.markChecked(at: date) }
    }

    /// Drops the account's ledger, when the account is removed from the app. Returns false when it had none.
    @discardableResult
    public func removeAccount(_ account: String) throws(SmallStoreError) -> Bool {
        let key = try AccountKey.forWriting(account)
        return try state.mutate { document in document.accounts.removeValue(forKey: key) != nil }
    }

    // MARK: Recovery

    /// Reads the stored data again, for example after the user restored a file. Returns the failure if any.
    @discardableResult
    public func reload() -> SmallStoreError? {
        state.reload()
    }

    /// Sets the unreadable data aside (a `.corrupt` copy for files, never a deletion) and starts from empty ledgers.
    /// Only call it after the user agreed: this is the single way out of a failed load.
    public func discardUnreadableData() throws(SmallStoreError) {
        try state.discardUnreadableData()
    }

    // MARK: Internals

    private func update(_ account: String, _ change: (inout NotificationLedger) -> Bool) throws(SmallStoreError) -> Bool {
        let key = try AccountKey.forWriting(account)
        return try state.mutate { document in
            var ledger = document.accounts[key] ?? NotificationLedger()
            guard change(&ledger) else { return false }
            document.accounts[key] = ledger
            return true
        }
    }
}
