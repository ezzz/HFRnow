/// Why a mutation, a merge or a write of the MPStorage document was refused.
public enum MPStorageError: Error, Sendable, Hashable {
    /// No `data` entry has the version this app writes (`0.1`): the document is never rewritten blindly.
    case noWritableEntry
    /// A character outside the Basic Multilingual Plane (most emoji): HFR silently truncates the post there
    /// (HFR-PROTOCOL §6, Q-3). `path` locates it, `codePoint` is its scalar value.
    case nonBMPCharacter(path: String, codePoint: UInt32)
    /// The JSON text holds a `\u` escape of a lone UTF-16 surrogate, which no Swift string can hold: the
    /// document is not readable as is (another client wrote broken text). `byteOffset` locates the escape.
    case unpairedSurrogate(byteOffset: Int)
    /// The serialized document exceeds the write cap (E24).
    case tooLarge(byteCount: Int, limit: Int)
}
