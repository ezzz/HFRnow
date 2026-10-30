/// The load-once state every small store holds, with `PseudoListStore`'s rule (audit E §7.2): a document that cannot be
/// read, or comes from a newer version, makes reads answer nothing and writes throw, so it is never saved over, until
/// `reload()` succeeds or `discardUnreadableData()` is called.
struct SmallStoreState<Document: SmallStoreDocument> {
    private enum Phase {
        case unloaded
        case loaded(Document)
        case failed(SmallStoreError)
    }

    private let persistence: any SmallStorePersistence<Document>
    private var phase = Phase.unloaded

    /// Creates a state over `persistence`; nothing is read until the first call.
    init(persistence: any SmallStorePersistence<Document>) {
        self.persistence = persistence
    }

    /// The document, loading it if needed; nil while the stored data is unreadable.
    mutating func document() -> Document? {
        if case .loaded(let document) = load() { return document }
        return nil
    }

    /// The reason writes are refused, or nil when the store is usable (loading it if needed).
    mutating func failure() -> SmallStoreError? {
        if case .failed(let error) = load() { return error }
        return nil
    }

    /// Reads the stored data again. Returns the failure if any.
    mutating func reload() -> SmallStoreError? {
        phase = .unloaded
        return failure()
    }

    /// Sets the unreadable data aside and starts from an empty document; does nothing when the store is usable.
    mutating func discardUnreadableData() throws(SmallStoreError) {
        guard case .failed = load() else { return }
        do {
            try persistence.quarantineUnreadableData()
        } catch {
            throw .saveFailed(reason: String(describing: error))
        }
        phase = .loaded(.empty)
    }

    /// Applies `change` to a copy, persists it, then publishes it: memory never gets ahead of the disk.
    /// Returns false, and saves nothing, when `change` returns false.
    mutating func mutate(_ change: (inout Document) throws(SmallStoreError) -> Bool) throws(SmallStoreError) -> Bool {
        switch load() {
        case .failed(let error):
            throw error
        case .unloaded:
            throw .loadFailed(reason: "unreachable state")
        case .loaded(let current):
            var updated = current
            guard try change(&updated) else { return false }
            do {
                try persistence.save(updated)
            } catch {
                throw .saveFailed(reason: String(describing: error))
            }
            phase = .loaded(updated)
            return true
        }
    }

    private mutating func load() -> Phase {
        guard case .unloaded = phase else { return phase }
        do {
            let stored = try persistence.load() ?? .empty
            if stored.version > Document.currentVersion {
                phase = .failed(.unsupportedVersion(stored.version))
            } else if stored.version < 1 {
                // Every format starts at 1: a lower number is not a document this code or an older one wrote.
                phase = .failed(.loadFailed(reason: "invalid version \(stored.version)"))
            } else {
                phase = .loaded(stored)
            }
        } catch let error as SmallStoreError {
            phase = .failed(error)
        } catch {
            phase = .failed(.loadFailed(reason: String(describing: error)))
        }
        return phase
    }
}
