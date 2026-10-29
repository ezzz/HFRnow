import Foundation
import HFRClient
import HFRModels
import HFRNetwork
import HFRStorage
@testable import SwiftHFR
import Testing

/// The LOT-044 session check wired into the accounts (#300): outcome mapping, launch check, quiet re-check.
@MainActor
struct ForumSessionCheckTests {
    private func session(user: String) -> HFRSession {
        HFRSession(cookies: Fake.cookies(user: user), hashCheck: "fake-hash")
    }

    private func check(_ reply: ScriptedRefresher.Reply) async -> SessionCheckResult {
        await ForumSessionCheck(refresher: ScriptedRefresher(["user1": [reply]])).check(session(user: "user1"))
    }

    // MARK: - Mapping

    @Test func everyFlowOutcomeMapsToItsCheckResult() async {
        #expect(await check(.success(.valid)) == .valid)
        #expect(await check(.success(.expired(.noIdentityCookie))) == .expired)
        // LOT-044: a page that proves nothing never logs out.
        #expect(await check(.success(.unconfirmed(.unrecognizedPage))) == .unconfirmed)
        #expect(await check(.success(.unconfirmed(.identityNotConfirmed))) == .unconfirmed)
        #expect(await check(.success(.unconfirmed(.sessionChanged))) == .unconfirmed)
    }

    @Test func transportFailuresAreFailedAndCancellationIsUnconfirmed() async throws {
        let url = try #require(URL(string: "https://forum.hardware.fr/user/editprofil.php?config=hfr.inc&page=1"))
        for error: NetworkError in [.offline, .timedOut, .httpStatus(code: 500, url: url), .transport(code: -1)] {
            #expect(await check(.failure(error)) == .failed(error))
        }
        #expect(await check(.failure(.cancelled)) == .unconfirmed)
    }

    /// The real flow behind a forum that answers nothing: a jar without a usable `md_user` is `expired` and nothing is
    /// sent (LOT-044 step 1). A request would get `.unscripted` and show up in `forum.sent`.
    @Test func liveFlowExpiresJarsWithoutIdentityAndKeepsTheirCookies() async {
        let forum = CapturedForum([:])
        let lapsed = StoredCookie(name: "md_user", value: "user1", domain: ".hardware.fr", expiresDate: Fake.now.addingTimeInterval(-60))
        let deleted = StoredCookie(name: "md_user", value: "deleted", domain: ".hardware.fr", expiresDate: Fake.tomorrow)
        let pass = StoredCookie(name: "md_passs", value: "fake-pass", domain: ".hardware.fr", expiresDate: Fake.tomorrow)
        for cookies in [[pass], [pass, lapsed], [pass, deleted]] {
            let jar = HFRSession(cookies: cookies, hashCheck: "fake-hash")
            let before = await jar.cookies().map(\.value)
            #expect(await ForumSessionCheck(refresher: forum.flow).check(jar) == .expired)
            #expect(await jar.cookies().map(\.value) == before)
            #expect(await jar.hashCheck == "fake-hash")
        }
        #expect(forum.sent.isEmpty)
    }

    // MARK: - Launch

    @Test func launchCheckConfirmsReportsAndNeverLogsOut() async throws {
        var noIdentity = Fake.account("user5")
        noIdentity.cookies = [StoredCookie(name: "md_passs", value: "fake-pass", domain: ".hardware.fr", expiresDate: Fake.tomorrow)]
        let store = try InMemoryCredentialStore(accounts: [
            Fake.account("user1", main: true), Fake.account("user2"), Fake.account("user3"), Fake.account("user4"), noIdentity
        ])
        let refresher = ScriptedRefresher([
            "user1": [.success(.valid)],
            "user2": [.success(.unconfirmed(.identityNotConfirmed))], // stale cookies: not captured yet (#281)
            "user3": [.success(.unconfirmed(.unrecognizedPage))],
            "user4": [.failure(.offline)]
        ])
        let model = makeModel(store: store, checker: ForumSessionCheck(refresher: refresher))

        await model.restore()

        #expect(model.rows.map(\.status) == [.valid, .restored, .restored, .checkFailed(.offline), .expired])
        #expect(refresher.calls == ["user1", "user2", "user3", "user4"])
        // `valid` persists what the forum refreshed.
        let stored = try store.accounts()
        #expect(stored[0].cookies.first { $0.name == "md_passs" }?.value == "refreshed-pass")
        #expect(stored[0].hashCheck == "refreshed-hash")
        // Nothing else is written, removed or logged out.
        for (index, account) in stored.enumerated().dropFirst() {
            let original = index == 4 ? noIdentity : Fake.account(account.pseudo)
            #expect(account.cookies == original.cookies)
            #expect(account.hashCheck == "fake-hash")
        }
        for id in ["user2", "user3", "user4"] {
            let session = try #require(model.session(for: id))
            #expect(await session.isLoggedIn())
        }
        #expect(model.current?.id == "user1")
    }

    // MARK: - Quiet re-check

    @Test func recheckRetriesOnlyUnconfirmedSessionsAfterTheInterval() async throws {
        let store = try InMemoryCredentialStore(accounts: [
            Fake.account("user1", main: true), Fake.account("user2"), Fake.account("user3"), Fake.account("user4")
        ])
        let refresher = ScriptedRefresher([
            "user1": [.failure(.offline), .success(.valid)],
            "user2": [.success(.unconfirmed(.unrecognizedPage)), .failure(.timedOut)],
            "user3": [.success(.valid)],
            "user4": [.success(.expired(.noIdentityCookie))]
        ])
        let model = makeModel(store: store, checker: ForumSessionCheck(refresher: refresher))
        await model.restore()
        #expect(model.rows.map(\.status) == [.checkFailed(.offline), .restored, .valid, .expired])

        // Coming back right away sends nothing.
        await model.recheckUnconfirmedSessions()
        #expect(refresher.calls.count == 4)

        await model.recheckUnconfirmedSessions(now: Date().addingTimeInterval(AccountsModel.recheckInterval + 1))

        // Only the unconfirmed ones went back to the forum; valid and expired ones were left alone.
        #expect(refresher.calls == ["user1", "user2", "user3", "user4", "user1", "user2"])
        #expect(model.rows.map(\.status) == [.valid, .checkFailed(.timedOut), .valid, .expired])
        #expect(try store.mainAccount()?.cookies.first { $0.name == "md_passs" }?.value == "refreshed-pass")
        #expect(try store.accounts()[1].cookies == Fake.account("user2").cookies)
        #expect(!model.isRechecking)
    }

    // A gate a broken guard never reaches would hang the run: fail instead.
    @Test(.timeLimit(.minutes(1))) func recheckDuringTheLaunchCheckSendsNothingMore() async throws {
        let store = try InMemoryCredentialStore(accounts: [Fake.account("user1", main: true)])
        let gate = CheckGate()
        let refresher = ScriptedRefresher(["user1": [.failure(.offline)]], gate: gate)
        let model = makeModel(store: store, checker: ForumSessionCheck(refresher: refresher))

        let restoring = Task { await model.restore() }
        await gate.entered()
        // The launch check is running: the session is `checking`, not re-checked.
        await model.recheckUnconfirmedSessions(now: Date().addingTimeInterval(AccountsModel.recheckInterval + 1))
        await gate.open()
        await restoring.value

        #expect(refresher.calls == ["user1"])
        #expect(model.rows.map(\.status) == [.checkFailed(.offline)])
    }

    // The launch check has already marked user1 `checkFailed` and waits on user2: a re-check then would send a second
    // request for user1 while the launch pass still runs.
    @Test(.timeLimit(.minutes(1))) func recheckWhileTheLaunchCheckWaitsOnAnotherAccountSendsNothing() async throws {
        let store = try InMemoryCredentialStore(accounts: [Fake.account("user1", main: true), Fake.account("user2")])
        let gate = CheckGate()
        let refresher = ScriptedRefresher(
            ["user1": [.failure(.timedOut)], "user2": [.success(.unconfirmed(.unrecognizedPage))]], gate: gate, gatedCall: 2
        )
        let model = makeModel(store: store, checker: ForumSessionCheck(refresher: refresher))

        let restoring = Task { await model.restore() }
        await gate.entered()
        #expect(model.rows.map(\.status) == [.checkFailed(.timedOut), .checking])
        await model.recheckUnconfirmedSessions(now: Date().addingTimeInterval(AccountsModel.recheckInterval + 1))
        await gate.open()
        await restoring.value

        #expect(refresher.calls == ["user1", "user2"])
        #expect(model.rows.map(\.status) == [.checkFailed(.timedOut), .restored])
    }

    // A gate a broken guard never reaches would hang the run: fail instead.
    @Test(.timeLimit(.minutes(1))) func secondRecheckWhileOneRunsSendsNothing() async throws {
        let store = try InMemoryCredentialStore(accounts: [Fake.account("user1", main: true)])
        let gate = CheckGate()
        let refresher = ScriptedRefresher(["user1": [.failure(.offline), .success(.valid)]], gate: gate, gatedCall: 2)
        let model = makeModel(store: store, checker: ForumSessionCheck(refresher: refresher))
        await model.restore()
        let later = Date().addingTimeInterval(AccountsModel.recheckInterval + 1)

        let first = Task { await model.recheckUnconfirmedSessions(now: later) }
        await gate.entered()
        #expect(model.isRechecking)
        await model.recheckUnconfirmedSessions(now: later)
        await gate.open()
        await first.value

        #expect(refresher.calls == ["user1", "user1"])
        #expect(model.rows.map(\.status) == [.valid])
        #expect(!model.isRechecking)
    }

    // A gate a broken guard never reaches would hang the run: fail instead.
    @Test(.timeLimit(.minutes(1))) func loginDuringARecheckWinsOverItsResult() async throws {
        let store = try InMemoryCredentialStore(accounts: [Fake.account("user1", main: true)])
        let gate = CheckGate()
        let refresher = ScriptedRefresher(
            ["user1": [.success(.unconfirmed(.unrecognizedPage)), .failure(.offline)]], gate: gate, gatedCall: 2
        )
        let login = ScriptedLogin([.success(
            userKey: "user1", displayName: "user1", cookies: Fake.cookies(user: "user1", pass: "fake-pass-2"),
            hashCheck: "login-hash", avatarURL: nil
        )])
        let model = makeModel(store: store, login: login, checker: ForumSessionCheck(refresher: refresher))
        await model.restore()

        let later = Date().addingTimeInterval(AccountsModel.recheckInterval + 1)
        let rechecking = Task { await model.recheckUnconfirmedSessions(now: later) }
        await gate.entered()
        try await model.logIn(pseudo: "user1", password: "fake", for: .existing(id: "user1", displayName: "user1"))
        await gate.open()
        await rechecking.value

        #expect(model.rows.map(\.status) == [.valid])
        #expect(try store.mainAccount()?.hashCheck == "login-hash")
    }

    // A re-login renews the same `HFRSession`, so only the login-save count tells the write-back its jar is stale.
    @Test(.timeLimit(.minutes(1))) func loginSavedWhileACheckWritesBackWinsOverItsCookies() async throws {
        let store = try InMemoryCredentialStore(accounts: [Fake.account("user1", main: true)])
        let refresher = ScriptedRefresher(["user1": [.success(.unconfirmed(.unrecognizedPage)), .success(.valid)]])
        let login = ScriptedLogin([.success(
            userKey: "user1", displayName: "user1", cookies: Fake.cookies(user: "user1", pass: "fake-pass-2"),
            hashCheck: "login-hash", avatarURL: nil
        )])
        let model = makeModel(store: store, login: login, checker: ForumSessionCheck(refresher: refresher))
        await model.restore()
        let session = try #require(model.session(for: "user1"))

        // The re-check's write-back has read the refreshed jar; the re-login lands and is saved before it writes.
        model.beforePersistWrite = { [model] in
            model.beforePersistWrite = nil
            try? await model.logIn(pseudo: "user1", password: "fake", for: .existing(id: "user1", displayName: "user1"))
        }
        await model.recheckUnconfirmedSessions(now: Date().addingTimeInterval(AccountsModel.recheckInterval + 1))

        #expect(login.calls.count == 1)
        #expect(model.session(for: "user1") === session)
        #expect(model.rows.map(\.status) == [.valid])
        #expect(try store.mainAccount()?.hashCheck == "login-hash")
        #expect(try store.mainAccount()?.cookies.first { $0.name == "md_passs" }?.value == "fake-pass-2")
    }
}
