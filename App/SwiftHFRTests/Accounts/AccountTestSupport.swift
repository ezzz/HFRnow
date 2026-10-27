import Foundation
import HFRClient
import HFRModels
import HFRNetwork
import HFRStorage
@testable import SwiftHFR
import Synchronization
import UIKit

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

/// A one-shot barrier: `wait()` suspends until `open()`; `entered()` waits until someone is suspended in `wait()`.
actor CheckGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var arrivals: [CheckedContinuation<Void, Never>] = []
    private var arrived = false

    func wait() async {
        arrived = true
        arrivals.forEach { $0.resume() }
        arrivals = []
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func entered() async {
        if arrived { return }
        await withCheckedContinuation { arrivals.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}

/// Holds a task so a test double can cancel it from inside the work it runs.
final class TaskBox: Sendable {
    private let task = Mutex<Task<Void, any Error>?>(nil)

    func set(_ task: Task<Void, any Error>) { self.task.withLock { $0 = task } }

    func cancel() { task.withLock { $0 }?.cancel() }
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
    /// Runs after the cookies are installed and before the result returns (to interleave another action).
    let beforeReturn = Mutex<(@Sendable () async -> Void)?>(nil)

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
            if let hook = beforeReturn.withLock({ $0 }) { await hook() }
            return LoginResult(userKey: userKey, displayName: displayName, avatarURL: avatarURL)
        }
    }
}

/// Returns a scripted result per account and can change the session first, as a forum refresh would.
final class ScriptedChecker: SessionChecking {
    private let results: [String: SessionCheckResult]
    private let refreshedPass: String?
    private let identityAfter: String?
    private let gate: CheckGate?
    private let count = Mutex(0)

    /// `identityAfter` makes the forum set `md_user` to that value (`deleted`, another pseudo) before answering;
    /// `gate` suspends every check until opened.
    init(
        _ results: [String: SessionCheckResult], refreshedPass: String? = nil, identityAfter: String? = nil, gate: CheckGate? = nil
    ) {
        self.results = results
        self.refreshedPass = refreshedPass
        self.identityAfter = identityAfter
        self.gate = gate
    }

    var checks: Int { count.withLock { $0 } }

    func check(_ session: HFRSession) async -> SessionCheckResult {
        count.withLock { $0 += 1 }
        guard let user = await session.userKey() else { return .expired }
        await gate?.wait()
        let result = results[user] ?? .unconfirmed
        if let identityAfter {
            let identity = StoredCookie(name: "md_user", value: identityAfter, domain: ".hardware.fr", expiresDate: Fake.tomorrow)
            await session.mergeCookies([identity])
        }
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

    /// A real 2×2 PNG, so the model can decode it.
    static let png: Data = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).pngData { context in
        UIColor.red.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
    }

    init(data: Data? = RecordingAvatars.png) {
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
