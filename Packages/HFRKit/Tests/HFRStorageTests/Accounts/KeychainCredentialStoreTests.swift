#if canImport(Security)
import Foundation
import HFRModels
import Testing
@testable import HFRStorage

/// Runs against the real Keychain only when `HFR_KEYCHAIN_TESTS=1`: the data-protection Keychain needs a signed
/// host with a Keychain entitlement (app or device test target); a plain `swift test` binary gets
/// `errSecMissingEntitlement`. The store's rules are covered on every platform through `CredentialStoreTests`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["HFR_KEYCHAIN_TESTS"] == "1"))
struct KeychainCredentialStoreTests {
    private let store = KeychainCredentialStore(service: "hfr.tests.\(UUID().uuidString)")

    @Test func roundTripPromotionAndCleanup() throws {
        defer { try? store.removeAll() }
        #expect(try store.accounts().isEmpty)
        try store.save(makeAccount("alice", hash: "fake-hash"))
        try store.save(makeAccount("bob"))
        #expect(try store.mainAccount()?.pseudo == "bob")
        try store.deleteAccount(pseudo: "bob")
        #expect(try store.mainAccount()?.hashCheck == "fake-hash")
        try store.removeAll()
        #expect(try store.accounts().isEmpty)
    }
}
#endif
