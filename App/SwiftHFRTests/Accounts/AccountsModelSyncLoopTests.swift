import Foundation
import HFRModels
import HFRNetwork
import HFRStorage
@testable import SwiftHFR
import Synchronization
import Testing

/// The launch loop of #1276 (device trace of 2026-11-25): each valid check of the current account was followed by another
/// check and a session change (the #1231 reloads of the home page and the lists), 12 turns in 2.7 s. The check's write-back
/// is a refresh pushed to the iCloud copy; a copy dated later than this device's clock wins the merge and came back as a
/// replacement of the same login, adopted, signalled and checked again. Two devices share one synchronizable item.
@MainActor
struct AccountsModelSyncLoopTests {
    private let item = InMemorySecureDataItem()

    private func device(
        _ accounts: [Account], checker: any SessionChecking, login: ScriptedLogin = ScriptedLogin([]),
        clock: @escaping @Sendable () -> Date = { Date() }
    ) throws -> AccountsModel {
        let store = try InMemoryCredentialStore(accounts: accounts)
        let sync = AccountSync(accounts: store, item: item, state: InMemorySecureDataItem(), clock: clock)
        return AccountsModel(store: store, loginService: login, checker: checker, avatars: RecordingAvatars(), sync: sync)
    }

    /// Device B, whose clock is an hour ahead, took the account from A's copy and wrote it back: the copy is dated in A's future.
    private func copyDatedAhead() async throws {
        let deviceB = try device([], checker: ScriptedChecker([:]), clock: { Date().addingTimeInterval(3_600) })
        deviceB.reconcileAccountSync()
        await deviceB.restore()
        // The first write-back stores the jar's form of the cookies: a refresh, dated by B's clock, pushed to the copy.
        await deviceB.persistSession(of: "user1")
    }

    /// Awaits the sync checks until no new one starts.
    private func settle(_ model: AccountsModel) async {
        var awaited: Task<Void, Never>?
        while let task = model.syncCheckTask, task != awaited {
            await task.value
            awaited = task
        }
    }

    @Test("#1276: a launch check that confirms the same login is checked once and is not a session change")
    func aValidLaunchCheckIsNotEchoedBackByTheSync() async throws {
        let checker = RewritingChecker()
        let deviceA = try device([Fake.account("user1", main: true)], checker: checker)
        deviceA.setAccountSync(true)
        try await copyDatedAhead()

        await deviceA.restore()
        await settle(deviceA)

        // At dev-swift: one check per turn until the checker stops answering (`RewritingChecker.limit`).
        #expect(checker.checks == 1)
        #expect(deviceA.currentSessionChanges == 0)
        #expect(deviceA.rows.first?.status == .valid)
    }

    @Test("#1231 kept: a re-login on another device with new credentials is adopted, checked once and signalled once")
    func newCredentialsFromAnotherDeviceStillSignalTheChange() async throws {
        let checker = RewritingChecker()
        let deviceA = try device([Fake.account("user1", main: true)], checker: checker)
        deviceA.setAccountSync(true)
        await deviceA.restore()
        await settle(deviceA)
        let script = LoginScript.success(
            userKey: "user1", displayName: "user1", cookies: Fake.cookies(user: "user1", pass: "fake-new"),
            hashCheck: "fake-hash-2", avatarURL: nil
        )
        let deviceB = try device([], checker: ScriptedChecker([:]), login: ScriptedLogin([script]))
        deviceB.reconcileAccountSync()
        await deviceB.restore()
        try await deviceB.logIn(pseudo: "user1", password: "fake-password", for: .existing(id: "user1", displayName: "user1"))

        deviceA.reconcileAccountSync()
        await settle(deviceA)

        #expect(checker.checks == 2)
        #expect(deviceA.currentSessionChanges == 1)
        let session = try #require(deviceA.session(for: "user1"))
        #expect(await session.cookies().first { $0.name == "md_passs" }?.value == "fake-new")
        #expect(deviceA.rows.first?.status == .valid)
    }
}

/// Answers `valid` and sends the jar's login cookies again with a new expiry, as every logged-in HFR answer does
/// (HFR-PROTOCOL.md §6c, `R74`); past `limit` checks it times out, so a loop ends instead of hanging the test.
final class RewritingChecker: SessionChecking {
    static let limit = 12
    private let count = Mutex(0)

    var checks: Int { count.withLock { $0 } }

    func check(_ session: HFRSession) async -> SessionCheckResult {
        let turn = count.withLock { value -> Int in
            value += 1
            return value
        }
        guard turn <= Self.limit else { return .failed(.timedOut) }
        guard let user = await session.userKey() else { return .expired }
        let pass = await session.cookies().first { $0.name == "md_passs" }?.value ?? "fake-pass"
        let expiry = Date().addingTimeInterval(30 * 86_400 + Double(turn))
        await session.mergeCookies([
            StoredCookie(name: "md_passs", value: pass, domain: ".hardware.fr", expiresDate: expiry),
            StoredCookie(name: "md_user", value: user, domain: ".hardware.fr", expiresDate: expiry)
        ])
        return .valid
    }
}
