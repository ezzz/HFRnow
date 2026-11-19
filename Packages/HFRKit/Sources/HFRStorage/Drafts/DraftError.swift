/// Failures of the draft store.
public enum DraftError: Error, Sendable, Equatable {
    /// The stored drafts could not be read (not a format problem); writes are refused until `reload()` succeeds.
    case loadFailed(reason: String)
    /// The drafts could not be persisted; memory was left unchanged.
    case saveFailed(reason: String)
    /// The account's key (`AccountKey`) is empty: a draft belongs to an account (#1184). Nothing was stored.
    case emptyAccount
}
