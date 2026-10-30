import Synchronization

/// Memory persistence for tests and previews.
public final class InMemoryReadingPositionPersistence: ReadingPositionPersistence {
    private let stored: Mutex<ReadingPositionDocument?>

    /// Creates a persistence, optionally already holding a document.
    public init(_ document: ReadingPositionDocument? = nil) {
        stored = Mutex(document)
    }

    /// The document currently stored.
    public var document: ReadingPositionDocument? {
        stored.withLock { $0 }
    }

    public func load() throws -> ReadingPositionDocument? {
        stored.withLock { $0 }
    }

    public func save(_ document: ReadingPositionDocument) throws {
        stored.withLock { $0 = document }
    }

    public func quarantineUnreadableData() throws {
        stored.withLock { $0 = nil }
    }
}
