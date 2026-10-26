import Synchronization

/// Memory persistence for tests and previews.
public final class InMemoryDraftPersistence: DraftPersistence {
    private let stored: Mutex<DraftDocument?>

    /// Creates a persistence, optionally already holding a document.
    public init(_ document: DraftDocument? = nil) {
        stored = Mutex(document)
    }

    /// The document currently stored.
    public var document: DraftDocument? {
        stored.withLock { $0 }
    }

    public func load() throws -> DraftDocument? {
        stored.withLock { $0 }
    }

    public func save(_ document: DraftDocument) throws {
        stored.withLock { $0 = document }
    }

    public func quarantineUnreadableData() throws {
        stored.withLock { $0 = nil }
    }
}
