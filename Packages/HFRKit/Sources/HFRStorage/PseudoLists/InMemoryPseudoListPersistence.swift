import Synchronization

/// Memory persistence for tests and previews.
public final class InMemoryPseudoListPersistence: PseudoListPersistence {
    private let stored: Mutex<PseudoListDocument?>

    /// Creates a persistence, optionally already holding a document.
    public init(_ document: PseudoListDocument? = nil) {
        stored = Mutex(document)
    }

    /// The document currently stored.
    public var document: PseudoListDocument? {
        stored.withLock { $0 }
    }

    public func load() throws -> PseudoListDocument? {
        stored.withLock { $0 }
    }

    public func save(_ document: PseudoListDocument) throws {
        stored.withLock { $0 = document }
    }

    public func quarantineUnreadableData() throws {
        stored.withLock { $0 = nil }
    }
}
