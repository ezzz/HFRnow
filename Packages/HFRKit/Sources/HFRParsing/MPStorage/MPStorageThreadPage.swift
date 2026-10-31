import HFRModels

/// The storage thread page, read (LOT-038).
public enum MPStorageThreadPage: Sendable, Hashable {
    /// The storage message and its document.
    case storage(MPStorageMessage)
    /// HFR's "Ce message ne vous est pas destiné" page: the account cannot see this thread (deleted, or another member's),
    /// so a cached `post` is stale and the caller looks for the thread again (`MPStorage.m:837-849`).
    case notAddressed
}

/// The first message of the storage thread: the one clients edit, and the JSON it holds.
public struct MPStorageMessage: Sendable, Hashable {
    /// `numreponse` of the message, which an update edits (`MPStorage.m:880-881`).
    public var numreponse: Int
    /// The JSON text as the page shows it, U+00A0 removed, exactly as handed to `MPStorageCodec.decode`.
    public var text: String
    /// The decoded document.
    public var document: MPStorageDocument

    /// Creates a storage message.
    public init(numreponse: Int, text: String, document: MPStorageDocument) {
        self.numreponse = numreponse
        self.text = text
        self.document = document
    }
}
