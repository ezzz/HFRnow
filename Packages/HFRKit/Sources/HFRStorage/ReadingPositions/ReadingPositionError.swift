/// Failures of the reading-position store.
public enum ReadingPositionError: Error, Sendable, Equatable {
    /// The account identifier is empty.
    case emptyAccount
    /// The topic number is not positive, or the position is out of range (page below 1, message number not positive,
    /// negative offset). Nothing was stored.
    case invalidPosition
    /// The stored data could not be read or decoded; the store refuses to write so the data is not overwritten.
    case loadFailed(reason: String)
    /// The stored data comes from a newer format version; the store refuses to write.
    case unsupportedVersion(Int)
    /// The change could not be persisted; memory was left unchanged.
    case saveFailed(reason: String)
}
