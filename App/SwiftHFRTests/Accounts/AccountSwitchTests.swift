import Foundation
import HFRNetwork
import HFRStorage
@testable import SwiftHFR
import Testing

/// The forum screens' environment follows the current account (LOT-081 wiring of LOT-082's `AppEnvironment`).
@MainActor
struct AccountSwitchTests {
    @Test func environmentUsesTheCurrentAccountsSessionAndName() async throws {
        let store = try InMemoryCredentialStore(accounts: [Fake.account("user1", main: true), Fake.account("user2")])
        let model = makeModel(store: store)
        await model.restore()

        let first = AppEnvironment.current(of: model)
        #expect(first.session === model.session(for: "user1"))
        #expect(await first.accountName() == "user1")
        #expect(await first.isLoggedIn())

        let generation = model.currentSessionGeneration
        try model.select("user2")
        #expect(model.currentSessionGeneration != generation)
        let second = AppEnvironment.current(of: model)
        #expect(second.session === model.session(for: "user2"))
        #expect(await second.accountName() == "user2")
    }

    @Test func currentAccountAddedAgainGivesScreensItsNewSession() async throws {
        let store = try InMemoryCredentialStore(accounts: [Fake.account("user1", main: true)])
        let login = ScriptedLogin([.success(
            userKey: "user1", displayName: "user1", cookies: Fake.cookies(user: "user1", pass: "new"), hashCheck: "h", avatarURL: nil
        )])
        let model = makeModel(store: store, login: login)
        await model.restore()
        let before = AppEnvironment.current(of: model)
        let generation = model.currentSessionGeneration

        try await model.logIn(pseudo: "user1", password: "fake-password", for: .newAccount)

        #expect(model.current?.id == "user1")
        #expect(model.currentSessionGeneration != generation)
        let after = AppEnvironment.current(of: model)
        #expect(after.session !== before.session)
        #expect(after.session === model.currentSession)
    }

    @Test func loggedOutScreensShareOneSessionWithoutAnyAccountsCookies() async throws {
        let store = try InMemoryCredentialStore(accounts: [Fake.account("user1", main: true)])
        let model = makeModel(store: store)
        await model.restore()
        let account = try #require(model.currentSession)

        try model.remove("user1")

        let first = AppEnvironment.current(of: model)
        let second = AppEnvironment.current(of: model)
        #expect(first.session === second.session)
        #expect(first.session !== account)
        #expect(await first.accountName() == nil)
        #expect(await first.isLoggedIn() == false)
        #expect(await first.session.cookies().isEmpty)
    }
}
