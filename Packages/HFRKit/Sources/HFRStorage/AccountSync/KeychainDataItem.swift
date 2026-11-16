#if canImport(Security)
import Foundation
import Security

/// The four `SecItem` calls, so tests can check the exact queries an item sends (a scripted double) without a signed host.
public protocol KeychainCalls: Sendable {
    /// `SecItemCopyMatching`.
    func copyMatching(_ query: [String: Any]) -> (status: OSStatus, data: Data?)
    /// `SecItemAdd`.
    func add(_ attributes: [String: Any]) -> OSStatus
    /// `SecItemUpdate`.
    func update(_ query: [String: Any], _ attributes: [String: Any]) -> OSStatus
}

/// The real Keychain.
public struct SystemKeychainCalls: KeychainCalls {
    /// Creates the system calls.
    public init() {}

    /// `SecItemCopyMatching` returning data.
    public func copyMatching(_ query: [String: Any]) -> (status: OSStatus, data: Data?) {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result as? Data)
    }

    /// `SecItemAdd`.
    public func add(_ attributes: [String: Any]) -> OSStatus {
        SecItemAdd(attributes as CFDictionary, nil)
    }

    /// `SecItemUpdate`.
    public func update(_ query: [String: Any], _ attributes: [String: Any]) -> OSStatus {
        SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }
}

/// One generic-password item of the data-protection Keychain, described by a `KeychainItemDescriptor` (LOT-173). Writes
/// update the item, or add it when missing, and re-apply the accessibility class each time (LOT-065 rule). Nothing logs.
public struct KeychainDataItem: SecureDataItem {
    /// `kSecAttrService`, normally the bundle identifier.
    public let service: String
    /// Account name, accessibility and synchronizable flag.
    public let descriptor: KeychainItemDescriptor
    /// Keychain access group, if any.
    public let accessGroup: String?
    private let calls: any KeychainCalls

    /// Creates an item.
    public init(
        service: String, descriptor: KeychainItemDescriptor, accessGroup: String? = nil, calls: any KeychainCalls = SystemKeychainCalls()
    ) {
        self.service = service
        self.descriptor = descriptor
        self.accessGroup = accessGroup
        self.calls = calls
    }

    /// The query naming this item. `kSecAttrSynchronizable` is always explicit: a query without it matches only
    /// non-synchronizable items, so the synchronizable copy and a device-only item never alias.
    func baseQuery() -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: descriptor.accountName,
            kSecAttrSynchronizable as String: descriptor.isSynchronizable,
            kSecUseDataProtectionKeychain as String: true
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        return query
    }

    /// The `kSecAttrAccessible` value of the descriptor.
    var accessibleValue: CFString {
        switch descriptor.accessibility {
        case .afterFirstUnlock: kSecAttrAccessibleAfterFirstUnlock
        case .afterFirstUnlockThisDeviceOnly: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        }
    }

    /// The stored bytes; nil when the item does not exist.
    public func read() throws -> Data? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let (status, data) = calls.copyMatching(query)
        switch status {
        case errSecSuccess:
            guard let data else { throw CredentialStoreError.corrupted }
            return data
        case errSecItemNotFound:
            return nil
        default:
            throw CredentialStoreError.keychain(status: status)
        }
    }

    /// Updates the item, or adds it when missing.
    public func write(_ data: Data) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: accessibleValue
        ]
        let status = calls.update(baseQuery(), attributes)
        if status == errSecItemNotFound {
            let added = calls.add(baseQuery().merging(attributes) { _, new in new })
            guard added == errSecSuccess else { throw CredentialStoreError.keychain(status: added) }
        } else if status != errSecSuccess {
            throw CredentialStoreError.keychain(status: status)
        }
    }
}
#endif
