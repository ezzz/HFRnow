import Foundation
import HFRModels
import Synchronization

/// A store that keeps the envelope in memory, for tests and previews. It still goes through
/// `CredentialEnvelope`, so it behaves like the persistent stores (versioning, corruption).
public final class InMemoryCredentialStore: CredentialStore {
    private let storage: Mutex<Data?>

    /// Creates a store holding `envelope` (raw bytes, possibly invalid, for tests), or nothing.
    public init(envelope: Data? = nil) {
        storage = Mutex(envelope)
    }

    /// Creates a store holding these accounts.
    public convenience init(accounts: [Account]) throws {
        self.init(envelope: try CredentialEnvelope.encode(AccountBook(accounts: accounts)))
    }

    /// The raw envelope currently held; tests replace it to simulate other versions or corruption.
    public var envelope: Data? {
        get { storage.withLock { $0 } }
        set { storage.withLock { $0 = newValue } }
    }

    /// The stored accounts.
    public func load() throws -> AccountBook {
        try storage.withLock { data in try data.map(CredentialEnvelope.decode) ?? AccountBook() }
    }

    /// Read-modify-write under the store's lock.
    public func update<Value>(_ body: (inout AccountBook) throws -> Value) throws -> Value {
        try storage.withLock { data in
            var book = try data.map(CredentialEnvelope.decode) ?? AccountBook()
            let original = book
            let value = try body(&book)
            if book != original {
                data = try CredentialEnvelope.encode(book)
            }
            return value
        }
    }

    /// Forgets everything.
    public func removeAll() throws {
        storage.withLock { $0 = nil }
    }
}
