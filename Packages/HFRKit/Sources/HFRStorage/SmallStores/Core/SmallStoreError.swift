/// Failures of the small stores (LOT-064).
public enum SmallStoreError: Error, Sendable, Equatable {
    /// The account identifier is empty once its account key is computed.
    case emptyAccount
    /// The value cannot be stored (empty code or section, topic number not positive). Nothing was stored.
    case invalidValue(reason: String)
    /// The stored data could not be read or decoded; the store refuses to write so the data is not overwritten.
    case loadFailed(reason: String)
    /// The stored data comes from a newer format version; the store refuses to write.
    case unsupportedVersion(Int)
    /// The change could not be persisted; memory was left unchanged.
    case saveFailed(reason: String)
}
