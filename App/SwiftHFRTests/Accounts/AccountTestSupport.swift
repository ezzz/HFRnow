import Foundation
import HFRClient
import HFRModels
import HFRNetwork
import HFRStorage
@testable import SwiftHFR
import Synchronization

/// Fake test data: cookie values, tokens and pseudos are made up.
enum Fake {
    static let now = Date()
    static let tomorrow = now.addingTimeInterval(86_400)

    static func cookies(user: String, pass: String = "fake-pass") -> [StoredCookie] {
        [
            StoredCookie(name: "md_passs", value: pass, domain: ".hardware.fr", expiresDate: tomorrow),
            StoredCookie(name: "md_user", value: user, domain: ".hardware.fr", expiresDate: tomorrow)
        ]
    }

    static func account(_ user: String, display: String? = nil, main: Bool = false, hash: String = "fake-hash") -> Account {
        Account(pseudo: user, displayName: display, cookies: cookies(user: user), hashCheck: hash, isMain: main)
    }
}

/// One scripted login: what HFR "answers" and what the flow would install.
enum LoginScript: Sendable {
    case success(userKey: String, displayName: String, cookies: [StoredCookie], hashCheck: String, avatarURL: URL?)
    case failure(LoginError)
}

/// Records the calls and, on success, installs the cookies and token in the target session as `LoginFlow` does.
final class ScriptedLogin: AccountLoggingIn {
    struct Call: Sendable {
        let pseudo: String
        let expectedUserKey: String?
        let session: ObjectIdentifier
    }

    private let state: Mutex<(scripts: [LoginScript], calls: [Call])>

    init(_ scripts: [LoginScript]) {
        state = Mutex((scripts, []))
    }

    var calls: [Call] { state.withLock { $0.calls } }

    func logIn(
        pseudo: String, password: String, into session: HFRSession, expectedUserKey: String?
    ) async throws(LoginError) -> LoginResult {
        let script: LoginScript = state.withLock { state in
            state.calls.append(Call(pseudo: pseudo, expectedUserKey: expectedUserKey, session: ObjectIdentifier(session)))
            return state.scripts.isEmpty ? .failure(.network(.unscripted)) : state.scripts.removeFirst()
        }
        switch script {
        case .failure(let error):
            throw error
        case let .success(userKey, displayName, cookies, hashCheck, avatarURL):
            await session.replaceCookies(with: cookies)
            await session.updateHashCheck(hashCheck)
            return LoginResult(userKey: userKey, displayName: displayName, avatarURL: avatarURL)
        }
    }
}

/// Returns a scripted result per account and can change the session first, as a forum refresh would.
final class ScriptedChecker: SessionChecking {
    private let results: [String: SessionCheckResult]
    private let refreshedPass: String?
    private let count = Mutex(0)

    init(_ results: [String: SessionCheckResult], refreshedPass: String? = nil) {
        self.results = results
        self.refreshedPass = refreshedPass
    }

    var checks: Int { count.withLock { $0 } }

    func check(_ session: HFRSession) async -> SessionCheckResult {
        count.withLock { $0 += 1 }
        guard let user = await session.userKey() else { return .expired }
        let result = results[user] ?? .unconfirmed
        if result == .valid, let refreshedPass {
            await session.mergeCookies(Fake.cookies(user: user, pass: refreshedPass))
            await session.updateHashCheck("refreshed-hash")
        }
        return result
    }
}

/// Returns fixed bytes and records the URLs asked.
final class RecordingAvatars: AvatarLoading {
    private let urls = Mutex<[URL]>([])
    let data: Data?

    init(data: Data? = Data([0x89, 0x50, 0x4E, 0x47])) {
        self.data = data
    }

    var requested: [URL] { urls.withLock { $0 } }

    func avatarData(at url: URL) async -> Data? {
        urls.withLock { $0.append(url) }
        return data
    }
}

/// An in-memory store whose writes can be made to fail like a locked Keychain.
final class FlakyStore: CredentialStore {
    let inner: InMemoryCredentialStore
    let failWrites = Mutex(false)

    init(accounts: [Account] = []) throws {
        inner = try InMemoryCredentialStore(accounts: accounts)
    }

    func load() throws -> AccountBook { try inner.load() }

    func update<Value>(_ body: (inout AccountBook) throws -> Value) throws -> Value {
        if failWrites.withLock({ $0 }) { throw CredentialStoreError.keychain(status: -25_308) }
        return try inner.update(body)
    }

    func removeAll() throws { try inner.removeAll() }
}

@MainActor
func makeModel(
    store: any CredentialStore,
    login: ScriptedLogin = ScriptedLogin([]),
    checker: any SessionChecking = LocalSessionCheck(),
    avatars: RecordingAvatars = RecordingAvatars()
) -> AccountsModel {
    AccountsModel(store: store, loginService: login, checker: checker, avatars: avatars)
}
