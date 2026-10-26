/// Why a credential store refused to read or write. Cases never carry cookie values, tokens or stored bytes.
public enum CredentialStoreError: Error, Sendable, Hashable {
    /// The stored envelope is not valid JSON of the expected shape. Nothing is overwritten: `removeAll()` is
    /// the only way out, and it is the caller's decision.
    case corrupted
    /// The envelope was written by a newer app version; reading or rewriting it could lose data.
    case unsupportedVersion(Int)
    /// Empty pseudo, or the logged-out marker `deleted` (A §4.1).
    case invalidPseudo
    /// The account's `md_user` cookie names another pseudo than the account (legacy `MultisManager.m:55-60`).
    case pseudoMismatch
    /// A Keychain call failed with this `OSStatus`.
    case keychain(status: Int32)
}
