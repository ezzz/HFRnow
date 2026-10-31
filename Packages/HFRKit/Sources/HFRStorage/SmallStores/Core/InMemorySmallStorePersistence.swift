import Synchronization

/// Memory persistence for tests and previews.
public final class InMemorySmallStorePersistence<Document: SmallStoreDocument>: SmallStorePersistence {
    private let stored: Mutex<Document?>

    /// Creates a persistence, optionally already holding a document.
    public init(_ document: Document? = nil) {
        stored = Mutex(document)
    }

    /// The document currently stored.
    public var document: Document? {
        stored.withLock { $0 }
    }

    public func load() throws -> Document? {
        stored.withLock { $0 }
    }

    public func save(_ document: Document) throws {
        stored.withLock { $0 = document }
    }

    public func quarantineUnreadableData() throws {
        stored.withLock { $0 = nil }
    }
}
