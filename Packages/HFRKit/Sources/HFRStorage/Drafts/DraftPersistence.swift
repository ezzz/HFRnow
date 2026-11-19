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
    /// Nothing to copy by default (in-memory stores and test doubles keep no file).
    public func backUpUnreadableData() throws {}
}
