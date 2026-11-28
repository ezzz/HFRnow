import Foundation
import HFRModels
import HFRNetwork
import HFRStorage
@testable import SwiftHFR
import Testing

/// #1420 review (Fable, finding 1): another device's copy of the same login without `md_id` (a legacy import, a login past
/// 30 days), dated ahead, must not take this device's `md_id` away, neither from the store (so a relaunch keeps it) nor from
/// the session; with the app running (case a) and when the copy arrives while it is not (case b). Adapted from the review's
/// probe. Nothing is sent: in-memory items and a scripted checker.
@MainActor
struct AccountsModelMemberIDSyncTests {
    private let item = InMemorySecureDataItem()
    private static let memberID = StoredCookie(
        name: "md_id", value: "900001", domain: ".hardware.fr", expiresDate: Date().addingTimeInterval(86_400)
    )

    private func model(
        _ store: InMemoryCredentialStore, state: InMemorySecureDataItem, checker: RewritingChecker = RewritingChecker()
    ) -> AccountsModel {
        let sync = AccountSync(accounts: store, item: item, state: state, clock: { Date() })
        return AccountsModel(store: store, loginService: ScriptedLogin([]), checker: checker, avatars: RecordingAvatars(), sync: sync)
    }

    /// Device B's write-back of the same login, without `md_id`, dated an hour ahead.
    private func plantCopyDatedAhead() throws {
        let current = try AccountSyncEnvelope.decode(try #require(item.data))
        let enabledAt = try #require(current.enabledAt)
        let account = Account(
            pseudo: "user1", displayName: "user1", cookies: Fake.cookies(user: "user1"), hashCheck: "fake-hash-b", isMain: true
        )
        let ahead = Date().addingTimeInterval(3_600)
        let entry = SyncedAccount(account: account, stamp: AccountStamp(credentialsAt: ahead, consentAt: .distantPast))
        item.data = try AccountSyncEnvelope.full(enabledAt: enabledAt, accounts: [entry], removed: [:]).encoded()
    }

    private func settle(_ model: AccountsModel) async {
        var awaited: Task<Void, Never>?
        while let task = model.syncCheckTask, task != awaited {
            await task.value
            awaited = task
        }
    }

    private struct Device {
        let store: InMemoryCredentialStore
        let state: InMemorySecureDataItem
        let model: AccountsModel
        let checker: RewritingChecker
    }

    /// Device A, logged in with `md_id`, sync on, its session checked valid.
    private func deviceA() async throws -> Device {
        var account = Fake.account("user1", main: true)
        account.cookies.append(Self.memberID)
        let store = try InMemoryCredentialStore(accounts: [account])
        let state = InMemorySecureDataItem()
        let checker = RewritingChecker()
        let device = model(store, state: state, checker: checker)
        device.setAccountSync(true)
        await device.restore()
        await settle(device)
        #expect(device.rows.first?.status == .valid)
        #expect(await device.session(for: "user1")?.holdsMemberID() == true)
        return Device(store: store, state: state, model: device, checker: checker)
    }

    private func relaunchHoldsMemberID(_ device: Device) async throws -> Bool {
        let relaunched = model(device.store, state: device.state)
        relaunched.reconcileAccountSync()
        await relaunched.restore()
        await settle(relaunched)
        let session = try #require(relaunched.session(for: "user1"))
        return await session.holdsMemberID()
    }

    @Test func caseARunningAppKeepsMemberIDInTheSessionTheStoreAndAfterARelaunch() async throws {
        let device = try await deviceA()
        try plantCopyDatedAhead()
        device.model.reconcileAccountSync()
        await settle(device.model)
        #expect(await device.model.session(for: "user1")?.holdsMemberID() == true)
        let stored = try #require(try device.store.load().account(matching: "user1"))
        #expect(stored.cookies.contains { $0.name == "md_id" })
        // #1385: the same login is neither adopted nor checked again.
        #expect(device.checker.checks == 1)
        #expect(device.model.currentSessionChanges == 0)
        #expect(try await relaunchHoldsMemberID(device))
    }

    @Test func caseBACopyArrivingWhileTheAppIsNotRunningKeepsMemberIDAtLaunch() async throws {
        let device = try await deviceA()
        try plantCopyDatedAhead()
        #expect(try await relaunchHoldsMemberID(device))
    }
}
