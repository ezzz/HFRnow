import Foundation
import HFRClient
import HFRNetwork
import HFRStorage
@testable import SwiftHFR
import Testing

@MainActor
struct LoginModelTests {
    @Test func submitNeedsBothFieldsAndNoRunningAttempt() {
        let model = LoginModel(target: .newAccount, accounts: makeModel(store: InMemoryCredentialStore()))
        #expect(!model.canSubmit)
        model.pseudo = "   "
        model.password = "fake-password"
        #expect(!model.canSubmit)
        model.pseudo = "user1"
        model.password = ""
        #expect(!model.canSubmit)
        model.password = "fake-password"
        #expect(model.canSubmit)
    }

    @Test func refusedLoginShowsWhyAndKeepsTheFields() async {
        let accounts = makeModel(store: InMemoryCredentialStore(), login: ScriptedLogin([.failure(.invalidCredentials)]))
        let model = LoginModel(target: .newAccount, accounts: accounts)
        model.pseudo = "user1"
        model.password = "fake-password"

        model.submit()
        #expect(model.isSubmitting)
        #expect(!model.canSubmit)
        await model.waitForSubmission()

        #expect(model.errorMessage == AccountMessages.message(for: LoginError.invalidCredentials))
        #expect(!model.isSubmitting)
        #expect(!model.didSucceed)
        #expect(model.password == "fake-password")
        #expect(accounts.rows.isEmpty)
    }

    @Test func successfulLoginClearsThePasswordAndFinishes() async {
        let accounts = makeModel(store: InMemoryCredentialStore(), login: ScriptedLogin([.success(
            userKey: "user1", displayName: "user1", cookies: Fake.cookies(user: "user1"), hashCheck: "h", avatarURL: nil
        )]))
        let model = LoginModel(target: .newAccount, accounts: accounts)
        model.pseudo = "user1"
        model.password = "fake-password"

        model.submit()
        await model.waitForSubmission()

        #expect(model.didSucceed)
        #expect(model.password.isEmpty)
        #expect(model.errorMessage == nil)
        #expect(accounts.current?.id == "user1")
    }

    @Test func cancelledLoginShowsNothing() async {
        let accounts = makeModel(store: InMemoryCredentialStore(), login: ScriptedLogin([.failure(.network(.cancelled))]))
        let model = LoginModel(target: .newAccount, accounts: accounts)
        model.pseudo = "user1"
        model.password = "fake-password"
        model.submit()
        await model.waitForSubmission()
        #expect(model.errorMessage == nil)
        #expect(!model.didSucceed)
        #expect(!model.isSubmitting)
    }

    @Test func reloginShowsTheAccountAndLocksThePseudo() {
        let model = LoginModel(
            target: .existing(id: "user%20two", displayName: "user two"), accounts: makeModel(store: InMemoryCredentialStore())
        )
        #expect(model.pseudo == "user two")
        #expect(!model.canEditPseudo)
    }
}

struct AccountMessagesTests {
    @Test func everyLoginErrorSaysWhatToDoExceptACancellation() {
        let errors: [LoginError] = [
            .missingCredentials, .invalidCredentials, .unrecognizedResponse, .missingIdentityCookie, .accountMismatch,
            .missingHashCheck, .network(.offline), .network(.timedOut), .network(.transport(code: -1)), .network(.invalidResponse),
            .network(.invalidRequest(reason: "x")), .network(.httpStatus(code: 503, url: URL(filePath: "/")))
        ]
        let messages = errors.compactMap { AccountMessages.message(for: $0) }
        #expect(messages.count == errors.count)
        #expect(Set(messages).count == messages.count - 2) // transport, invalidResponse and invalidRequest share one text
        #expect(AccountMessages.message(for: LoginError.network(.cancelled)) == nil)
        #expect(AccountMessages.message(for: LoginError.network(.httpStatus(code: 503, url: URL(filePath: "/"))))?.contains("503") == true)
    }

    @Test func storeErrorsAndProblemsHaveTexts() {
        let errors: [CredentialStoreError] = [.corrupted, .unsupportedVersion(2), .invalidPseudo, .pseudoMismatch, .keychain(status: -25_308)]
        #expect(errors.allSatisfy { !AccountMessages.message(for: $0).isEmpty })
        #expect(StoreProblem(.keychain(status: -25_308)) == .unavailable(status: -25_308))
        #expect(StoreProblem(.unsupportedVersion(3)) == .newerVersion)
        #expect(StoreProblem(.corrupted) == .corrupted)
        for problem in [StoreProblem.corrupted, .newerVersion, .unavailable(status: -1)] {
            #expect(!AccountMessages.message(for: problem).isEmpty)
        }
    }
}

struct AnonymousAvatarLoaderTests {
    private static let avatar = URL(string: "https://forum-images.hardware.fr/images/mesdiscussions-1.jpg")

    @Test(arguments: [
        "http://forum-images.hardware.fr/images/a.jpg",
        "https://forum-images.hardware.fr:8443/images/a.jpg",
        "https://forum-images.hardware.fr.example.com/images/a.jpg",
        "https://forum.hardware.fr/images/a.jpg",
        "https://example.com/a.jpg"
    ])
    func onlyTheForumImageHostOverHTTPSIsFetched(_ address: String) async throws {
        let url = try #require(URL(string: address))
        let transport = MockTransport(replies: [.success(HTTPResponse(statusCode: 200, url: url, body: Data([1])))])
        #expect(await AnonymousAvatarLoader(transport: transport).avatarData(at: url) == nil)
        #expect(await transport.requests.isEmpty)
    }

    @Test func avatarIsFetchedWithoutFollowingRedirects() async throws {
        let url = try #require(Self.avatar)
        let transport = MockTransport(replies: [.success(HTTPResponse(statusCode: 200, url: url, body: Data([1, 2])))])
        #expect(await AnonymousAvatarLoader(transport: transport).avatarData(at: url) == Data([1, 2]))
        #expect(await transport.requests.map(\.redirectPolicy) == [.doNotFollow])
    }

    @Test func redirectsErrorsAndOversizedBodiesGiveNoAvatar() async throws {
        let url = try #require(Self.avatar)
        let replies: [Result<HTTPResponse, NetworkError>] = [
            .success(HTTPResponse(statusCode: 302, headers: ["Location": "https://example.com/"], url: url)),
            .success(HTTPResponse(statusCode: 404, url: url, body: Data([1]))),
            .success(HTTPResponse(statusCode: 200, url: url)),
            .success(HTTPResponse(statusCode: 200, url: url, body: Data(count: AnonymousAvatarLoader.maximumBytes + 1))),
            .failure(.offline)
        ]
        let loader = AnonymousAvatarLoader(transport: MockTransport(replies: replies))
        for _ in replies {
            #expect(await loader.avatarData(at: url) == nil)
        }
    }
}
