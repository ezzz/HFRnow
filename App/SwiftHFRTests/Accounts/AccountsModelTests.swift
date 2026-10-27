import Foundation
import HFRClient
import HFRModels
import HFRNetwork
import HFRStorage
@testable import SwiftHFR
import Testing

@MainActor
struct AccountsModelRestoreTests {
    @Test func restoreRebuildsOneSessionPerAccountFromTheStore() async throws {
        let store = try InMemoryCredentialStore(accounts: [Fake.account("user1"), Fake.account("user2", display: "User2", main: true)])
        let model = makeModel(store: store)

        await model.restore()

        #expect(model.rows.map(\.id) == ["user1", "user2"])
        #expect(model.current?.id == "user2")
        #expect(model.current?.displayName == "User2")
        #expect(model.storeProblem == nil)
        let session = try #require(model.currentSession)
        #expect(await session.userKey() == "user2")
        #expect(await session.hashCheck == "fake-hash")
        #expect(await session.cookies().map(\.name) == ["md_passs", "md_user"])
        let other = try #require(model.session(for: "user1"))
        #expect(other !== session)
        #expect(await other.userKey() == "user1")
    }

    @Test func noStoredAccountMeansLoggedOut() async {
        let model = makeModel(store: InMemoryCredentialStore())
        await model.restore()
        #expect(model.rows.isEmpty)
        #expect(model.current == nil)
        #expect(model.currentSession == nil)
        #expect(model.hasRestored)
    }

    @Test func accountWithoutUsableIdentityIsExpiredOthersStayRestored() async throws {
        var loggedOut = Fake.account("user1")
        loggedOut.cookies = [StoredCookie(name: "md_passs", value: "fake-pass", domain: ".hardware.fr", expiresDate: Fake.tomorrow)]
        var lapsed = Fake.account("user3")
        lapsed.cookies = [StoredCookie(
            name: "md_user", value: "user3", domain: ".hardware.fr", expiresDate: Fake.now.addingTimeInterval(-60)
        )]
        let store = try InMemoryCredentialStore(accounts: [loggedOut, Fake.account("user2"), lapsed])
        let model = makeModel(store: store)

        await model.restore()

        #expect(model.rows.map(\.status) == [.expired, .restored, .expired])
        // Expired is a state, not a deletion: the stored cookies are kept for a re-login.
        #expect(try store.accounts().map(\.cookies.count) == [1, 2, 1])
    }

    @Test func validCheckPersistsWhatTheForumRefreshed() async throws {
        let store = try InMemoryCredentialStore(accounts: [Fake.account("user1", main: true)])
        let checker = ScriptedChecker(["user1": .valid], refreshedPass: "fake-pass-2")
        let model = makeModel(store: store, checker: checker)

        await model.restore()

        #expect(model.current?.status == .valid)
        let stored = try #require(try store.mainAccount())
        #expect(stored.cookies.first { $0.name == "md_passs" }?.value == "fake-pass-2")
        #expect(stored.hashCheck == "refreshed-hash")
    }

    @Test func validCheckOfAJarThatLostItsIdentityWritesNothing() async throws {
        let store = try InMemoryCredentialStore(accounts: [Fake.account("user1", main: true)])
        let before = store.envelope
        let model = makeModel(store: store, checker: ScriptedChecker(["user1": .valid], logsOut: true))

        await model.restore()

        #expect(store.envelope == before)
        #expect(model.storeProblem == nil)
    }

    @Test func failedWriteAfterAValidCheckIsReported() async throws {
        let store = try FlakyStore(accounts: [Fake.account("user1", main: true)])
        store.failWrites.withLock { $0 = true }
        let model = makeModel(store: store, checker: ScriptedChecker(["user1": .valid], refreshedPass: "fake-pass-2"))

        await model.restore()

        #expect(model.storeProblem == .unavailable(status: -25_308))
        #expect(try store.mainAccount()?.cookies.first { $0.name == "md_passs" }?.value == "fake-pass")
    }

    @Test func retryDuringARunningRestoreChecksEachSessionOnce() async throws {
        let store = try InMemoryCredentialStore(accounts: [Fake.account("user1", main: true)])
        let gate = Gate()
        let checker = ScriptedChecker([:], gate: gate)
        let model = makeModel(store: store, checker: checker)

        let restoring = Task { await model.restore() }
        await gate.entered()
        #expect(model.isRestoring)
        let retrying = Task { await model.retryRestore() }
        // Give a second restore every chance to reach the checker before the first one is released.
        for _ in 0..<200 where checker.checks < 2 { await Task.yield() }
        await gate.open()
        await restoring.value
        await retrying.value

        #expect(checker.checks == 1)
        #expect(!model.isRestoring)
    }

    @Test func checkOutcomesOtherThanValidWriteNothing() async throws {
        let store = try InMemoryCredentialStore(accounts: [Fake.account("user1"), Fake.account("user2")])
        let before = store.envelope
        let checker = ScriptedChecker(["user1": .failed(.offline), "user2": .unconfirmed], refreshedPass: "never")
        let model = makeModel(store: store, checker: checker)

        await model.restore()

        #expect(model.rows.map(\.status) == [.checkFailed(.offline), .restored])
        #expect(store.envelope == before)
    }

    @Test func restoreRunsOnceEvenWhenCalledConcurrently() async throws {
        let store = try InMemoryCredentialStore(accounts: [Fake.account("user1"), Fake.account("user2")])
        let checker = ScriptedChecker([:])
        let model = makeModel(store: store, checker: checker)

        async let first: Void = model.restore()
        async let second: Void = model.restore()
        _ = await (first, second)
        await model.restore()

        #expect(checker.checks == 2)
    }

    @Test func corruptedStoreIsReportedAndOnlyErasedOnRequest() async throws {
        let garbage = Data("not json".utf8)
        let store = InMemoryCredentialStore(envelope: garbage)
        let model = makeModel(store: store)

        await model.restore()
        #expect(model.storeProblem == .corrupted)
        #expect(model.rows.isEmpty)
        #expect(store.envelope == garbage)

        await model.eraseStoredAccounts()
        #expect(model.storeProblem == nil)
        #expect(store.envelope == nil)
    }

    @Test func newerStoreIsReportedAndNeverOverwritten() async throws {
        let newer = Data(#"{"version":2,"accounts":[]}"#.utf8)
        let store = InMemoryCredentialStore(envelope: newer)
        let model = makeModel(store: store, login: ScriptedLogin([
            .success(userKey: "user1", displayName: "user1", cookies: Fake.cookies(user: "user1"), hashCheck: "h", avatarURL: nil)
        ]))

        await model.restore()
        #expect(model.storeProblem == .newerVersion)
        await #expect(throws: AccountActionError.store(.unsupportedVersion(2))) {
            try await model.logIn(pseudo: "user1", password: "fake-password", for: .newAccount)
        }
        #expect(store.envelope == newer)
    }
}

@MainActor
struct AccountsModelLoginTests {
    @Test func newAccountIsStoredUnderItsUserKeyAndBecomesCurrent() async throws {
        let store = try InMemoryCredentialStore(accounts: [Fake.account("user1", main: true)])
        let login = ScriptedLogin([.success(
            userKey: "user%20two", displayName: "user two", cookies: Fake.cookies(user: "user%20two"),
            hashCheck: "new-hash", avatarURL: nil
        )])
        let model = makeModel(store: store, login: login)
        await model.restore()

        try await model.logIn(pseudo: " user two ", password: "fake-password", for: .newAccount)

        #expect(login.calls.map(\.expectedUserKey) == [nil])
        #expect(model.rows.map(\.id) == ["user1", "user%20two"])
        #expect(model.current?.id == "user%20two")
        #expect(model.current?.displayName == "user two")
        #expect(model.current?.status == .valid)
        let stored = try #require(try store.mainAccount())
        #expect(stored.pseudo == "user%20two")
        #expect(stored.hashCheck == "new-hash")
        #expect(stored.cookies.map(\.name) == ["md_passs", "md_user"])
        #expect(await model.currentSession?.userKey() == "user%20two")
    }

    @Test func everyLoginFailureLeavesStoreAndSessionsAsTheyWere() async throws {
        let failures: [LoginError] = [
            .missingCredentials, .invalidCredentials, .unrecognizedResponse, .missingIdentityCookie,
            .accountMismatch, .missingHashCheck, .network(.offline), .network(.httpStatus(code: 500, url: URL(filePath: "/"))),
            .network(.cancelled)
        ]
        for failure in failures {
            let store = try InMemoryCredentialStore(accounts: [Fake.account("user1", main: true)])
            let before = store.envelope
            let model = makeModel(store: store, login: ScriptedLogin([.failure(failure)]))
            await model.restore()
            let session = try #require(model.currentSession)
            let cookiesBefore = await session.cookies()
            #expect(cookiesBefore.map(\.name) == ["md_passs", "md_user"])

            await #expect(throws: AccountActionError.login(failure)) {
                try await model.logIn(pseudo: "user1", password: "fake-password", for: .existing(id: "user1", displayName: "user1"))
            }

            #expect(store.envelope == before)
            #expect(model.currentSession === session)
            #expect(await session.cookies() == cookiesBefore)
            #expect(model.current?.status == .restored)
        }
    }

    @Test func reloginRenewsTheAccountsOwnSessionAndKeepsTheCurrentAccount() async throws {
        let store = try InMemoryCredentialStore(accounts: [Fake.account("user1", main: true), Fake.account("user2")])
        let login = ScriptedLogin([.success(
            userKey: "user2", displayName: "user2", cookies: Fake.cookies(user: "user2", pass: "renewed"),
            hashCheck: "renewed-hash", avatarURL: nil
        )])
        let model = makeModel(store: store, login: login)
        await model.restore()
        let session = try #require(model.session(for: "user2"))

        try await model.logIn(pseudo: "user2", password: "fake-password", for: .existing(id: "user2", displayName: "user2"))

        #expect(login.calls.map(\.expectedUserKey) == ["user2"])
        #expect(login.calls.map(\.session) == [ObjectIdentifier(session)])
        #expect(model.session(for: "user2") === session)
        #expect(model.current?.id == "user1")
        #expect(model.rows.first { $0.id == "user2" }?.status == .valid)
        let stored = try #require(try store.load().account(matching: "user2"))
        #expect(stored.hashCheck == "renewed-hash")
        #expect(stored.cookies.first { $0.name == "md_passs" }?.value == "renewed")
    }

    @Test func reloginOfAnAccountNoLongerStoredSendsNothing() async throws {
        let login = ScriptedLogin([])
        let model = makeModel(store: InMemoryCredentialStore(), login: login)
        await model.restore()

        await #expect(throws: AccountActionError.unknownAccount) {
            try await model.logIn(pseudo: "user9", password: "fake-password", for: .existing(id: "user9", displayName: "user9"))
        }
        #expect(login.calls.isEmpty)
    }

    @Test func knownAccountTypedAgainReplacesItsSessionOnlyOnceStored() async throws {
        let store = try FlakyStore(accounts: [Fake.account("user1", main: true)])
        let script = LoginScript.success(
            userKey: "user1", displayName: "user1", cookies: Fake.cookies(user: "user1", pass: "new"),
            hashCheck: "new-hash", avatarURL: nil
        )
        let model = makeModel(store: store, login: ScriptedLogin([script, script]))
        await model.restore()
        let original = try #require(model.currentSession)

        store.failWrites.withLock { $0 = true }
        await #expect(throws: AccountActionError.store(.keychain(status: -25_308))) {
            try await model.logIn(pseudo: "USER1", password: "fake-password", for: .newAccount)
        }
        #expect(model.currentSession === original)
        #expect(await original.hashCheck == "fake-hash")
        #expect(try store.mainAccount()?.hashCheck == "fake-hash")

        store.failWrites.withLock { $0 = false }
        try await model.logIn(pseudo: "USER1", password: "fake-password", for: .newAccount)
        #expect(model.currentSession !== original)
        #expect(model.rows.map(\.id) == ["user1"])
        #expect(try store.mainAccount()?.hashCheck == "new-hash")
    }

    @Test func avatarIsFetchedAfterLoginAndStored() async throws {
        let store = InMemoryCredentialStore()
        let url = try #require(URL(string: "https://forum-images.hardware.fr/images/mesdiscussions-1.jpg"))
        let avatars = RecordingAvatars()
        let login = ScriptedLogin([.success(
            userKey: "user1", displayName: "user1", cookies: Fake.cookies(user: "user1"), hashCheck: "h", avatarURL: url
        )])
        let model = makeModel(store: store, login: login, avatars: avatars)
        await model.restore()

        try await model.logIn(pseudo: "user1", password: "fake-password", for: .newAccount)
        await model.avatarTask?.value

        #expect(avatars.requested == [url])
        #expect(model.current?.avatar != nil)
        #expect(try store.mainAccount()?.avatarData == avatars.data)
    }

    @Test func bytesThatAreNotAnImageAreNeverStored() async throws {
        let store = InMemoryCredentialStore()
        let url = try #require(URL(string: "https://forum-images.hardware.fr/images/mesdiscussions-1.jpg"))
        let login = ScriptedLogin([.success(
            userKey: "user1", displayName: "user1", cookies: Fake.cookies(user: "user1"), hashCheck: "h", avatarURL: url
        )])
        let model = makeModel(store: store, login: login, avatars: RecordingAvatars(data: Data("<html>".utf8)))

        try await model.logIn(pseudo: "user1", password: "fake-password", for: .newAccount)
        await model.avatarTask?.value

        #expect(model.current?.avatar == nil)
        #expect(try store.mainAccount()?.avatarData == nil)
    }

    @Test func accountRemovedWhileItsReloginRunsIsNotBroughtBack() async throws {
        let store = try InMemoryCredentialStore(accounts: [Fake.account("user1", main: true), Fake.account("user2")])
        let login = ScriptedLogin([.success(
            userKey: "user2", displayName: "user2", cookies: Fake.cookies(user: "user2"), hashCheck: "h", avatarURL: nil
        )])
        let model = makeModel(store: store, login: login)
        await model.restore()
        login.beforeReturn.withLock { $0 = { await MainActor.run { _ = try? model.remove("user2") } } }

        await #expect(throws: AccountActionError.unknownAccount) {
            try await model.logIn(pseudo: "user2", password: "fake-password", for: .existing(id: "user2", displayName: "user2"))
        }

        #expect(model.rows.map(\.id) == ["user1"])
        #expect(try store.accounts().map(\.pseudo) == ["user1"])
        #expect(model.session(for: "user2") == nil)
    }

    @Test func newAccountCancelledAfterTheLoginIsNotAdded() async throws {
        let store = try InMemoryCredentialStore(accounts: [Fake.account("user1", main: true)])
        let before = store.envelope
        let login = ScriptedLogin([.success(
            userKey: "user2", displayName: "user2", cookies: Fake.cookies(user: "user2"), hashCheck: "h", avatarURL: nil
        )])
        let model = makeModel(store: store, login: login)
        await model.restore()
        let running = TaskBox()
        login.beforeReturn.withLock { $0 = { running.cancel() } }

        let task = Task { try await model.logIn(pseudo: "user2", password: "fake-password", for: .newAccount) }
        running.set(task)
        await #expect(throws: AccountActionError.login(.network(.cancelled))) { try await task.value }

        #expect(store.envelope == before)
        #expect(model.rows.map(\.id) == ["user1"])
        #expect(model.current?.id == "user1")
    }

    @Test func loginThatFinishesDuringTheLaunchCheckWins() async throws {
        let store = try InMemoryCredentialStore(accounts: [Fake.account("user1", main: true)])
        let gate = Gate()
        let login = ScriptedLogin([.success(
            userKey: "user1", displayName: "user1", cookies: Fake.cookies(user: "user1"), hashCheck: "h", avatarURL: nil
        )])
        let model = makeModel(store: store, login: login, checker: ScriptedChecker(["user1": .expired], gate: gate))

        let restoring = Task { await model.restore() }
        await gate.entered()
        #expect(model.current?.status == .checking)
        try await model.logIn(pseudo: "user1", password: "fake-password", for: .existing(id: "user1", displayName: "user1"))
        await gate.open()
        await restoring.value

        #expect(model.current?.status == .valid)
    }

    @Test func noAvatarURLMeansNoDownload() async throws {
        let avatars = RecordingAvatars()
        let login = ScriptedLogin([.success(
            userKey: "user1", displayName: "user1", cookies: Fake.cookies(user: "user1"), hashCheck: "h", avatarURL: nil
        )])
        let model = makeModel(store: InMemoryCredentialStore(), login: login, avatars: avatars)
        try await model.logIn(pseudo: "user1", password: "fake-password", for: .newAccount)
        #expect(model.avatarTask == nil)
        #expect(avatars.requested.isEmpty)
    }
}

@MainActor
struct AccountsModelSelectionTests {
    @Test func selectMakesAnAccountCurrent() async throws {
        let store = try InMemoryCredentialStore(accounts: [Fake.account("user1", main: true), Fake.account("user2")])
        let model = makeModel(store: store)
        await model.restore()

        try model.select("user2")

        #expect(model.current?.id == "user2")
        #expect(try store.mainAccount()?.pseudo == "user2")
        #expect(await model.currentSession?.userKey() == "user2")
    }

    @Test func removingTheCurrentAccountPromotesTheFirstRemaining() async throws {
        let store = try InMemoryCredentialStore(accounts: [
            Fake.account("user1"), Fake.account("user2", main: true), Fake.account("user3")
        ])
        let model = makeModel(store: store)
        await model.restore()

        try model.remove("user2")

        #expect(model.rows.map(\.id) == ["user1", "user3"])
        #expect(model.current?.id == "user1")
        #expect(model.session(for: "user2") == nil)
        #expect(try store.accounts().map(\.pseudo) == ["user1", "user3"])
    }

    @Test func removingTheLastAccountLogsOut() async throws {
        let model = makeModel(store: try InMemoryCredentialStore(accounts: [Fake.account("user1")]))
        await model.restore()
        try model.remove("user1")
        #expect(model.current == nil)
        #expect(model.currentSession == nil)
    }

    @Test func unknownAccountsAndStoreFailuresAreReported() async throws {
        let store = try FlakyStore(accounts: [Fake.account("user1", main: true), Fake.account("user2")])
        let model = makeModel(store: store)
        await model.restore()

        #expect(throws: AccountActionError.unknownAccount) { try model.select("user9") }
        #expect(throws: AccountActionError.unknownAccount) { try model.remove("user9") }
        store.failWrites.withLock { $0 = true }
        #expect(throws: AccountActionError.store(.keychain(status: -25_308))) { try model.select("user2") }
        #expect(throws: AccountActionError.store(.keychain(status: -25_308))) { try model.remove("user2") }
        #expect(model.current?.id == "user1")
        #expect(model.rows.count == 2)
        #expect(model.session(for: "user2") != nil)
    }
}
