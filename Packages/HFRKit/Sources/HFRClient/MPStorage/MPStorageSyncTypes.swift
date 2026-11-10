import Foundation
import HFRModels
import HFRNetwork

/// What the device keeps of one account's MPStorage document, as the sync loop sees it (LOT-130). The app stores it
/// device-only (HFRStorage's `MPStorageCopyStore`); the texts hold member pseudos.
public struct MPStorageSyncCopy: Sendable, Hashable {
    /// The storage thread's id; nil until found.
    public var post: Int?
    /// The document text last read or written: the merge base (LOT-062).
    public var base: String?
    /// The document text with local edits not yet written; nil when there are none.
    public var pending: String?
    /// The last successful read or write.
    public var lastSync: Date?
    /// The last search of the MP list that found no thread.
    public var lastSearch: Date?

    /// Creates a copy.
    public init(post: Int? = nil, base: String? = nil, pending: String? = nil, lastSync: Date? = nil, lastSearch: Date? = nil) {
        self.post = post
        self.base = base
        self.pending = pending
        self.lastSync = lastSync
        self.lastSearch = lastSearch
    }

    /// The document the app shows: the local edits, else the last copy read; nil before the first read.
    public var currentText: String? { pending ?? base }
}

/// Where the sync loop keeps its copy (the app's adapter over HFRStorage).
public protocol MPStorageSyncPersistence: Sendable {
    /// The stored copy; an empty copy when none is stored.
    /// - Throws: `storage` when the stored data cannot be read.
    func load() async throws(MPStorageSyncError) -> MPStorageSyncCopy
    /// Replaces the stored copy.
    /// - Throws: `storage` when it cannot be saved.
    func save(_ copy: MPStorageSyncCopy) async throws(MPStorageSyncError)
}

/// The forum side of the sync loop: LOT-052's transport in the account's session (`LiveMPStorageRemote`).
public protocol MPStorageRemote: Sendable {
    /// The storage thread's id, or nil when the MP list ends without it.
    func findThread() async throws(MPStorageTransportError) -> Int?
    /// The document of thread `post`.
    func read(post: Int) async throws(MPStorageTransportError) -> MPStorageSnapshot
    /// Merges and writes `ours`, then reads it back.
    func save(
        _ ours: MPStorageDocument, base: MPStorageDocument?, at location: MPStorageLocation, stamp: MPStorageStamp
    ) async throws(MPStorageTransportError) -> MPStorageSaveResult
    /// Creates the thread unless one exists.
    func create(stamp: MPStorageStamp) async throws(MPStorageTransportError) -> MPStorageCreation
}

/// `MPStorageTransport` in the session of the account whose storage it is.
public struct LiveMPStorageRemote: MPStorageRemote {
    private let session: HFRSession
    private let transport = MPStorageTransport()

    /// Creates the remote over the account's session.
    public init(session: HFRSession) {
        self.session = session
    }

    /// See `MPStorageTransport.findThread(in:)`.
    public func findThread() async throws(MPStorageTransportError) -> Int? {
        try await transport.findThread(in: session)
    }

    /// See `MPStorageTransport.read(post:in:)`.
    public func read(post: Int) async throws(MPStorageTransportError) -> MPStorageSnapshot {
        try await transport.read(post: post, in: session)
    }

    /// See `MPStorageTransport.save(_:base:at:stamp:in:)`.
    public func save(
        _ ours: MPStorageDocument, base: MPStorageDocument?, at location: MPStorageLocation, stamp: MPStorageStamp
    ) async throws(MPStorageTransportError) -> MPStorageSaveResult {
        try await transport.save(ours, base: base, at: location, stamp: stamp, in: session)
    }

    /// See `MPStorageTransport.create(stamp:in:)`.
    public func create(stamp: MPStorageStamp) async throws(MPStorageTransportError) -> MPStorageCreation {
        try await transport.create(stamp: stamp, in: session)
    }
}

/// Why a sync call failed (LOT-130). A failure never drops the local edits.
public enum MPStorageSyncError: Error, Sendable, Equatable {
    /// The forum exchange failed (LOT-052; `posting(.unconfirmed)` and `notVerified` may have written).
    case transport(MPStorageTransportError)
    /// The device copy could not be read or saved.
    case storage(reason: String)
    /// No document was read yet: an edit needs a base to merge with.
    case notLoaded
    /// The stored copy is not a readable document.
    case unreadableCopy
    /// The edit or the edited document is refused (no `0.1` entry, a non-BMP character, too large): nothing was stored.
    case document(MPStorageError)
}

/// The result of `MPStorageSync.detect`.
public enum MPStorageDetection: Sendable, Equatable {
    /// The account has a storage thread; its document is now the device copy.
    case found
    /// The MP list ends without a storage thread.
    case notFound
}

/// The result of `MPStorageSync.sync`.
public enum MPStorageSyncOutcome: Sendable, Equatable {
    /// The copy is the forum's; `wrote` when local edits were written.
    case synced(wrote: Bool)
    /// The account has no storage thread (deleted elsewhere): nothing was written.
    case noThread
}
