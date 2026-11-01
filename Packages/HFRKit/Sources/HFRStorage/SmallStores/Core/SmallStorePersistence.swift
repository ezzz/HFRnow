/// Where a small store's document lives: a file in the app, memory in tests.
public protocol SmallStorePersistence<Document>: Sendable {
    /// The document this persistence holds.
    associatedtype Document: SmallStoreDocument

    /// The stored document, or nil when nothing has been stored yet. Throws when data exists but cannot be read or decoded.
    func load() throws -> Document?
    /// Replaces the stored document atomically: a crash leaves either the old or the new document.
    func save(_ document: Document) throws
    /// Sets unreadable data aside (never deletes it) so that a fresh document can be written.
    func quarantineUnreadableData() throws
}
