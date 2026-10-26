/// Failures of the draft store.
public enum DraftError: Error, Sendable, Equatable {
    /// The stored drafts could not be read (not a format problem); writes are refused until `reload()` succeeds.
    case loadFailed(reason: String)
    /// The drafts could not be persisted; memory was left unchanged.
    case saveFailed(reason: String)
}
