import Foundation
import HFRModels
import Testing
@testable import HFRStorage

/// The synchronizable item's envelope, the device state and the Keychain descriptors (LOT-173).
@Suite struct AccountSyncEnvelopeTests {
    @Test func aFullEnvelopeRoundTrips() throws {
        let envelope = AccountSyncEnvelope.full(
            enabledAt: moment(100.25),
            accounts: [SyncedAccount(
                account: fakeAccount("user-a"), stamp: AccountStamp(credentialsAt: moment(120.5), consentAt: moment(110))
            )],
            removed: ["user-x": moment(130)]
        )
        let data = try envelope.encoded()
        #expect(try AccountSyncEnvelope.decode(data) == envelope)
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains(#""updatedAt":130"#))
        #expect(!text.lowercased().contains("password"))
    }

    @Test(arguments: [
        #"{"version":1,"accounts":[]}"#,
        #"{"version":1,"enabledAt":1,"deletedAt":2,"accounts":[]}"#,
        #"{"version":0,"enabledAt":1,"accounts":[]}"#,
        #"[1]"#
    ])
    func malformedEnvelopesAreCorrupted(json: String) {
        #expect(throws: CredentialStoreError.corrupted) { try AccountSyncEnvelope.decode(Data(json.utf8)) }
    }

    @Test func aTombstoneHoldingAccountsIsCorrupted() throws {
        let entry = try JSONEncoder().encode(SyncedAccount(account: fakeAccount("user-a"), stamp: .unknown))
        let json = #"{"version":1,"deletedAt":2,"accounts":["# + (try #require(String(data: entry, encoding: .utf8))) + "]}"
        #expect(throws: CredentialStoreError.corrupted) { try AccountSyncEnvelope.decode(Data(json.utf8)) }
    }

    @Test func aNewerVersionIsRefused() {
        #expect(throws: CredentialStoreError.unsupportedVersion(2)) {
            try AccountSyncEnvelope.decode(Data(#"{"version":2,"deletedAt":2,"accounts":[]}"#.utf8))
        }
    }

    @Test func theStateRoundTripsAndAnUnreadableOneIsOff() throws {
        var state = AccountSyncState()
        state.isOn = true
        state.enabledAt = moment(100)
        state.honouredDeletedAt = moment(50)
        state.provisionalEnabledAt = moment(100)
        state.imported = ["user-a"]
        state.stamps = ["user-a": AccountStamp(credentialsAt: moment(90), consentAt: moment(80))]
        state.removed = ["user-x": moment(95)]
        #expect(AccountSyncState.decoded(from: try state.encoded()) == state)
        #expect(AccountSyncState.decoded(from: Data("garbage".utf8)) == AccountSyncState())
        #expect(AccountSyncState.decoded(from: Data(#"{"version":2,"isOn":true,"enabledAt":1}"#.utf8)) == AccountSyncState())
        #expect(!AccountSyncState.decoded(from: Data(#"{"version":1,"isOn":true}"#.utf8)).isOn)
    }

    /// ADR 0013 §6: the copy syncs and is `AfterFirstUnlock` (a `ThisDeviceOnly` class cannot sync); the state never leaves
    /// the device; neither aliases LOT-065's accounts item.
    @Test func theItemsHaveTheAccessAttributesOfTheSpec() {
        #expect(KeychainItemDescriptor.syncedAccounts.isSynchronizable)
        #expect(KeychainItemDescriptor.syncedAccounts.accessibility == .afterFirstUnlock)
        #expect(!KeychainItemDescriptor.syncState.isSynchronizable)
        #expect(KeychainItemDescriptor.syncState.accessibility == .afterFirstUnlockThisDeviceOnly)
        let names = [KeychainItemDescriptor.syncedAccounts.accountName, KeychainItemDescriptor.syncState.accountName]
        #expect(Set(names + ["hfr.accounts.v1"]).count == 3)
    }
}
