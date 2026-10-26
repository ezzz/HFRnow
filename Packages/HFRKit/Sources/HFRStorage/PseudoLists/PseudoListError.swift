/// Failures of the pseudo list store.
public enum PseudoListError: Error, Sendable, Equatable {
    /// The pseudo is empty once zero-width spaces are removed.
    case emptyPseudo
    /// The stored data could not be read or decoded; the store refuses to write so the data is not overwritten.
    case loadFailed(reason: String)
    /// The stored data comes from a newer format version; the store refuses to write.
    case unsupportedVersion(Int)
    /// The change could not be persisted; memory was left unchanged.
    case saveFailed(reason: String)
}
