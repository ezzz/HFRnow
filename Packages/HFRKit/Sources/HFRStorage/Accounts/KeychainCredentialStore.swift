#if canImport(Security)
import Foundation
import HFRModels
import Security
import Synchronization

/// The device store: one generic-password Keychain item holding the `CredentialEnvelope`.
/// Accessible after first unlock, this device only (Q-9: the background MP check runs while locked; tokens
/// are neither synced nor restored from a backup to another device), never synchronizable, in the
/// data-protection Keychain. Its item is separate from the legacy `HFR_COMPTES_KEY` one, which the import
/// (LOT-067) reads and never deletes.
public final class KeychainCredentialStore: CredentialStore {
    /// `kSecAttrAccount` of the item.
    public static let defaultAccountName = "hfr.accounts.v1"

    /// `kSecAttrService` of the item, normally the app's bundle identifier.
    public let service: String
    /// `kSecAttrAccount` of the item.
    public let accountName: String
    /// Keychain access group shared with app extensions, if any.
    public let accessGroup: String?
    private let lock = Mutex(())

    /// Creates a store for one Keychain item.
    public init(service: String, accountName: String = defaultAccountName, accessGroup: String? = nil) {
        self.service = service
        self.accountName = accountName
        self.accessGroup = accessGroup
    }

    /// The stored accounts; empty when the item does not exist.
    public func load() throws -> AccountBook {
        try lock.withLock { _ in try read() }
    }

    /// Read-modify-write under this instance's lock.
    public func update<Value>(_ body: (inout AccountBook) throws -> Value) throws -> Value {
        try lock.withLock { _ in
            var book = try read()
            let original = book
            let value = try body(&book)
            if book != original { try write(CredentialEnvelope.encode(book)) }
            return value
        }
    }

    /// Deletes the item; no error when it does not exist.
    public func removeAll() throws {
        try lock.withLock { _ in
            let status = SecItemDelete(baseQuery() as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw CredentialStoreError.keychain(status: status)
            }
        }
    }

    private func baseQuery() -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountName,
            kSecAttrSynchronizable as String: false,
            kSecUseDataProtectionKeychain as String: true
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        return query
    }

    private func read() throws -> AccountBook {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { throw CredentialStoreError.corrupted }
            return try CredentialEnvelope.decode(data)
        case errSecItemNotFound:
            return AccountBook()
        default:
            throw CredentialStoreError.keychain(status: status)
        }
    }

    /// Updates the item, or adds it when missing; the accessibility class is (re)applied on every write.
    private func write(_ data: Data) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemUpdate(baseQuery() as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let added = SecItemAdd(baseQuery().merging(attributes) { _, new in new } as CFDictionary, nil)
            guard added == errSecSuccess else { throw CredentialStoreError.keychain(status: added) }
        } else if status != errSecSuccess {
            throw CredentialStoreError.keychain(status: status)
        }
    }
}
#endif
