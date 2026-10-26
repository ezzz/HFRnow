import Foundation
import HFRModels

/// Persistence of the forum accounts (cookies, `hash_check`, avatar). No password is ever stored (E §5.1).
/// Implementations: `KeychainCredentialStore` (device), `FileCredentialStore` and `InMemoryCredentialStore`
/// (Linux, tests). Each serializes its own read-modify-write cycles; none logs what it stores.
public protocol CredentialStore: Sendable {
    /// The stored accounts; an empty book when nothing was ever stored.
    func load() throws -> AccountBook
    /// Reads, lets `body` change the book, and persists it when it changed, as one step for this store
    /// instance. Nothing is written when `body` throws or when reading failed (a corrupted or newer envelope
    /// is never overwritten). `body` must not call the same store: it runs under the store's lock.
    func update<Value>(_ body: (inout AccountBook) throws -> Value) throws -> Value
    /// Deletes everything this store persisted.
    func removeAll() throws
}

extension CredentialStore {
    /// Stored accounts, main flag included.
    public func accounts() throws -> [Account] {
        try load().accounts
    }

    /// The main account, if any.
    public func mainAccount() throws -> Account? {
        try load().main
    }

    /// Adds or refreshes an account (see `AccountBook.add`) and returns the stored value.
    @discardableResult
    public func save(_ account: Account, makeMain: Bool = true) throws -> Account {
        try update { try $0.add(account, makeMain: makeMain) }
    }

    /// Makes an account the main one; false when unknown.
    @discardableResult
    public func setMain(pseudo: String) throws -> Bool {
        try update { $0.setMain(pseudo: pseudo) }
    }

    /// Deletes an account, promoting another one when it was main; returns the deleted account.
    @discardableResult
    public func deleteAccount(pseudo: String) throws -> Account? {
        try update { $0.remove(pseudo: pseudo) }
    }
}
