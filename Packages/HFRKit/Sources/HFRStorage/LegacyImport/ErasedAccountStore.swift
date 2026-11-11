import Foundation
#if canImport(Security)
import Security
#endif
import Synchronization

/// The accounts the user erased from this device (LOT-157), so the legacy import (LOT-067) never brings them or their
/// legacy items back: legacy's `HFR_COMPTES_KEY` item is read-only for the import, so it still lists them. Keys are
/// `PseudoNormalizer.comparisonForm`. Kept in the Keychain, like that item, so a reinstall does not forget them.
public protocol ErasedAccountStore: Sendable {
    /// The erased accounts' keys.
    func keys() throws -> Set<String>
    /// Adds `pseudo`'s key; nothing changes when it is there (or empty).
    func insert(_ pseudo: String) throws
}

/// The stored form of the list: versioned, so a newer format is never overwritten.
enum ErasedAccountsEnvelope {
    static let currentVersion = 1

    private struct Document: Codable {
        var version: Int
        var keys: [String]
    }

    static func decode(_ data: Data) throws -> Set<String> {
        let document: Document
        do {
            document = try JSONDecoder().decode(Document.self, from: data)
        } catch {
            throw CredentialStoreError.corrupted
        }
        guard document.version >= 1 else { throw CredentialStoreError.corrupted }
        guard document.version <= currentVersion else { throw CredentialStoreError.unsupportedVersion(document.version) }
        return Set(document.keys)
    }

    static func encode(_ keys: Set<String>) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(Document(version: currentVersion, keys: keys.sorted()))
    }

    static func key(_ pseudo: String) -> String {
        PseudoNormalizer.comparisonForm(pseudo)
    }
}

/// The list in memory, for tests and previews; it goes through the same envelope as the Keychain store.
public final class InMemoryErasedAccountStore: ErasedAccountStore {
    private let storage: Mutex<Data?>

    /// Creates a store holding `envelope` (raw bytes, possibly invalid, for tests), or nothing.
    public init(envelope: Data? = nil) {
        storage = Mutex(envelope)
    }

    /// The erased keys.
    public func keys() throws -> Set<String> {
        try storage.withLock { data in try data.map(ErasedAccountsEnvelope.decode) ?? [] }
    }

    /// Adds `pseudo`'s key.
    public func insert(_ pseudo: String) throws {
        let key = ErasedAccountsEnvelope.key(pseudo)
        guard !key.isEmpty else { return }
        try storage.withLock { data in
            var keys = try data.map(ErasedAccountsEnvelope.decode) ?? []
            guard keys.insert(key).inserted else { return }
            data = try ErasedAccountsEnvelope.encode(keys)
        }
    }
}

#if canImport(Security)
/// The device list: one generic-password item next to the accounts' one, accessible after first unlock, this device only,
/// never synchronizable. It holds only the erased accounts' keys.
public final class KeychainErasedAccountStore: ErasedAccountStore {
    /// `kSecAttrAccount` of the item.
    public static let defaultAccountName = "hfr.legacyImport.erased.v1"

    /// `kSecAttrService` of the item, normally the app's bundle identifier.
    public let service: String
    /// `kSecAttrAccount` of the item.
    public let accountName: String
    private let lock = Mutex(())

    /// Creates a store for one Keychain item.
    public init(service: String, accountName: String = defaultAccountName) {
        self.service = service
        self.accountName = accountName
    }

    /// The erased keys; none when the item does not exist.
    public func keys() throws -> Set<String> {
        try lock.withLock { _ in try read() }
    }

    /// Adds `pseudo`'s key (read-modify-write under this instance's lock).
    public func insert(_ pseudo: String) throws {
        let key = ErasedAccountsEnvelope.key(pseudo)
        guard !key.isEmpty else { return }
        try lock.withLock { _ in
            var keys = try read()
            guard keys.insert(key).inserted else { return }
            try write(ErasedAccountsEnvelope.encode(keys))
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountName,
            kSecAttrSynchronizable as String: false,
            kSecUseDataProtectionKeychain as String: true
        ]
    }

    private func read() throws -> Set<String> {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { throw CredentialStoreError.corrupted }
            return try ErasedAccountsEnvelope.decode(data)
        case errSecItemNotFound:
            return []
        default:
            throw CredentialStoreError.keychain(status: status)
        }
    }

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
