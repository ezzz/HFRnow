/// Where drafts live. A file in the app, memory in tests.
public protocol DraftPersistence: Sendable {
    /// The stored document, or nil when nothing has been stored. Throws `DecodingError` for undecodable data and
    /// any other error for an I/O failure.
    func load() throws -> DraftDocument?
    /// Replaces the stored document atomically.
    func save(_ document: DraftDocument) throws
    /// Sets undecodable data aside (never deletes it).
    func quarantineUnreadableData() throws
}
