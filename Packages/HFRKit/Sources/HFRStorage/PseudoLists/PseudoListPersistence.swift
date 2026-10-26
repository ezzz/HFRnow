/// Where the pseudo lists live. A file in the app, memory in tests.
public protocol PseudoListPersistence: Sendable {
    /// The stored document, or nil when nothing has been stored yet. Throws when data exists but cannot be read or decoded.
    func load() throws -> PseudoListDocument?
    /// Replaces the stored document atomically: a crash leaves either the old or the new document.
    func save(_ document: PseudoListDocument) throws
    /// Sets unreadable data aside (never deletes it) so that a fresh document can be written.
    func quarantineUnreadableData() throws
}
