import Foundation

/// Where drafts live. A file in the app, memory in tests.
public protocol DraftPersistence: Sendable {
    /// The stored document, or nil when nothing has been stored. Throws `DecodingError` for undecodable data and
    /// any other error for an I/O failure.
    func load() throws -> DraftDocument?
    /// Replaces the stored document atomically.
    func save(_ document: DraftDocument) throws
    /// Sets undecodable data aside (never deletes it).
    func quarantineUnreadableData() throws
    /// Copies the stored data aside as it is, where `quarantineUnreadableData` would move it, and keeps it in place: the
    /// readable drafts of a file with unreadable entries are written back afterwards (#1183).
    func backUpUnreadableData() throws
}

extension DraftPersistence {
    /// Refuses by default: a persistence that keeps a file must copy it aside before the store writes the readable drafts
    /// back, and one that does not say so would let the store drop entries it never set aside. The store then blocks writes.
    public func backUpUnreadableData() throws {
        throw CocoaError(.featureUnsupported)
    }
}
