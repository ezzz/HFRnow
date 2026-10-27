import Foundation
import HFRClient
import HFRModels
import HFRNetwork
import HFRStorage
@testable import SwiftHFR
import Testing

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
