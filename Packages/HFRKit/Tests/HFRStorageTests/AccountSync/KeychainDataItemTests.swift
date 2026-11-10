#if canImport(Security)
import Foundation
import Security
import Synchronization
import Testing
@testable import HFRStorage

/// A scripted Keychain: records every query and answers from a dictionary keyed by account name and synchronizable flag,
/// as the data-protection Keychain does (an item is named by its attributes, `kSecAttrSynchronizable` included).
private final class ScriptedKeychain: KeychainCalls, @unchecked Sendable {
    struct Call {
        let name: String
        let query: [String: Any]
        let attributes: [String: Any]
    }

    private let lock = Mutex(())
    private var items: [String: Data] = [:]
    private(set) var calls: [Call] = []

    private func key(_ query: [String: Any]) -> String {
        "\(query[kSecAttrAccount as String] as? String ?? "")|\(query[kSecAttrSynchronizable as String] as? Bool ?? false)"
    }

    func copyMatching(_ query: [String: Any]) -> (status: OSStatus, data: Data?) {
        lock.withLock { _ in
            calls.append(Call(name: "copy", query: query, attributes: [:]))
            guard let data = items[key(query)] else { return (errSecItemNotFound, nil) }
            return (errSecSuccess, data)
        }
    }

    func add(_ attributes: [String: Any]) -> OSStatus {
        lock.withLock { _ in
            calls.append(Call(name: "add", query: attributes, attributes: attributes))
            items[key(attributes)] = attributes[kSecValueData as String] as? Data
            return errSecSuccess
        }
    }

    func update(_ query: [String: Any], _ attributes: [String: Any]) -> OSStatus {
        lock.withLock { _ in
            calls.append(Call(name: "update", query: query, attributes: attributes))
            guard items[key(query)] != nil else { return errSecItemNotFound }
            items[key(query)] = attributes[kSecValueData as String] as? Data
            return errSecSuccess
        }
    }
}

/// The exact `SecItem` queries of LOT-173's two items, without a signed host.
@Suite struct KeychainDataItemTests {
    @Test func theSynchronizableCopyIsAddedSynchronizableAndAfterFirstUnlock() throws {
        let keychain = ScriptedKeychain()
        let item = KeychainDataItem(service: "test.service", descriptor: .syncedAccounts, calls: keychain)
        #expect(try item.read() == nil)
        try item.write(Data("one".utf8))
        try item.write(Data("two".utf8))
        #expect(try item.read() == Data("two".utf8))

        #expect(keychain.calls.map(\.name) == ["copy", "update", "add", "update", "copy"])
        for call in keychain.calls {
            #expect(call.query[kSecAttrSynchronizable as String] as? Bool == true)
            #expect(call.query[kSecUseDataProtectionKeychain as String] as? Bool == true)
            #expect(call.query[kSecAttrService as String] as? String == "test.service")
            #expect(call.query[kSecAttrAccount as String] as? String == "hfr.accounts.sync.v1")
        }
        let add = try #require(keychain.calls.first { $0.name == "add" })
        #expect(add.attributes[kSecAttrAccessible as String] as? String == kSecAttrAccessibleAfterFirstUnlock as String)
        let update = try #require(keychain.calls.last { $0.name == "update" })
        #expect(update.attributes[kSecAttrAccessible as String] as? String == kSecAttrAccessibleAfterFirstUnlock as String)
    }

    @Test func theStateItemNeverLeavesTheDevice() throws {
        let keychain = ScriptedKeychain()
        let item = KeychainDataItem(service: "test.service", descriptor: .syncState, calls: keychain)
        try item.write(Data("state".utf8))
        let add = try #require(keychain.calls.first { $0.name == "add" })
        #expect(add.attributes[kSecAttrSynchronizable as String] as? Bool == false)
        #expect(add.attributes[kSecAttrAccessible as String] as? String == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        #expect(add.attributes[kSecAttrAccount as String] as? String == "hfr.accounts.sync-state.v1")
    }

    @Test func aKeychainFailureIsReportedWithItsStatusOnly() {
        struct Failing: KeychainCalls {
            func copyMatching(_ query: [String: Any]) -> (status: OSStatus, data: Data?) { (errSecInteractionNotAllowed, nil) }
            func add(_ attributes: [String: Any]) -> OSStatus { errSecMissingEntitlement }
            func update(_ query: [String: Any], _ attributes: [String: Any]) -> OSStatus { errSecItemNotFound }
        }
        let item = KeychainDataItem(service: "test.service", descriptor: .syncedAccounts, calls: Failing())
        #expect(throws: CredentialStoreError.keychain(status: errSecInteractionNotAllowed)) { try item.read() }
        #expect(throws: CredentialStoreError.keychain(status: errSecMissingEntitlement)) { try item.write(Data()) }
    }
}
#endif
