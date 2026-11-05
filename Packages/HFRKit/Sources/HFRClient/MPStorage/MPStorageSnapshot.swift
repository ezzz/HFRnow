import Foundation
import HFRModels

/// Where the account's MPStorage document lives: its private thread, the thread's first message and that message's edit
/// form (LOT-052). The app keeps `post` per account to skip the search next time; the rest is read again with it.
public struct MPStorageLocation: Sendable, Hashable {
    /// Thread id (`post=`) of the storage thread.
    public var post: Int
    /// Number of the first message, which holds the document.
    public var numreponse: Int
    /// The first message's edit link, as the thread page's toolbar printed it (`R60a` → `R60b`).
    public var editURL: URL

    /// Creates a location.
    public init(post: Int, numreponse: Int, editURL: URL) {
        self.post = post
        self.numreponse = numreponse
        self.editURL = editURL
    }
}

/// The document as HFR stores it: the edit form's `content_form`, byte for byte (`R60b`), and its decoded value.
public struct MPStorageSnapshot: Sendable, Hashable {
    /// Where it was read.
    public var location: MPStorageLocation
    /// The stored JSON text.
    public var text: String
    /// The decoded document; keep it as the `base` of the next save (LOT-062).
    public var document: MPStorageDocument

    /// Creates a snapshot.
    public init(location: MPStorageLocation, text: String, document: MPStorageDocument) {
        self.location = location
        self.text = text
        self.document = document
    }
}

/// Outcome of `MPStorageTransport.save`.
public struct MPStorageSaveResult: Sendable, Hashable {
    /// The stored copy: the one read back after the write, or the forum copy when nothing had to be written.
    public var snapshot: MPStorageSnapshot
    /// Concurrent changes the merge resolved (LOT-062), for the app to show or log.
    public var conflicts: [MPStorageConflict]
    /// Whether a write was sent and confirmed; false when the merge left the forum copy unchanged.
    public var wrote: Bool

    /// Creates a result.
    public init(snapshot: MPStorageSnapshot, conflicts: [MPStorageConflict], wrote: Bool) {
        self.snapshot = snapshot
        self.conflicts = conflicts
        self.wrote = wrote
    }
}

/// Outcome of `MPStorageTransport.create`.
public enum MPStorageCreation: Sendable, Hashable {
    /// The thread was created and read back.
    case created(MPStorageSnapshot)
    /// A storage thread already existed (another device, an earlier unconfirmed attempt): nothing was posted.
    case existing(MPStorageSnapshot)

    /// The snapshot, whichever way it was obtained.
    public var snapshot: MPStorageSnapshot {
        switch self {
        case .created(let snapshot), .existing(let snapshot): snapshot
        }
    }
}
