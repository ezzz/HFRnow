import Foundation
import HFRClient
import HFRModels
import HFRNetwork
import HFRStorage
import Observation

/// What the app knows about an account's session.
enum AccountSessionStatus: Sendable, Equatable {
    /// Restored from the store; the forum has not confirmed it (yet).
    case restored
    /// Being checked.
    case checking
    /// Confirmed by a login or a session check.
    case valid
    /// No usable identity: the account must log in again.
    case expired
    /// The check could not reach the forum; the session is kept.
    case checkFailed(NetworkError)
}

/// An account as the screens show it: no cookie, no token.
struct AccountRow: Sendable, Equatable, Identifiable {
    /// The account's key (`Account.pseudo`, the `md_user` value).
    let id: String
    /// Name shown in lists and menus.
    let displayName: String
    /// The current account, whose session the app uses.
    let isMain: Bool
    /// Avatar bytes, if downloaded.
    let avatarData: Data?
    /// Session state.
    let status: AccountSessionStatus
}

/// Which account a login is for.
enum LoginTarget: Sendable, Equatable, Identifiable {
    /// A new account, or a known one typed again (it is refreshed in place).
    case newAccount
    /// A known account whose session must be renewed; credentials of another account are refused.
    case existing(id: String, displayName: String)

    /// Identity for sheet presentation.
    var id: String {
        switch self {
        case .newAccount: "new"
        case .existing(let id, _): "existing:\(id)"
        }
    }
}

/// The accounts and their sessions: the single owner of `HFRSession`s in the app (LOT-081).
///
/// Mirrors the credential store (LOT-065): the account list is always what the store holds, and an account whose
/// store write failed is not shown. Each account has its own `HFRSession` (LOT-042), restored at launch from its stored
/// cookies and `hash_check`; the main account is the current one.
@MainActor
@Observable
final class AccountsModel {
    /// Accounts in store order.
    private(set) var rows: [AccountRow] = []
    /// A launch-time store problem, shown with its way out; nil when the store reads fine.
    private(set) var storeProblem: StoreProblem?
    /// True once `restore()` has read the store.
    private(set) var hasRestored = false

    @ObservationIgnored private let store: any CredentialStore
    @ObservationIgnored private let loginService: any AccountLoggingIn
    @ObservationIgnored private let checker: any SessionChecking
    @ObservationIgnored private let avatars: any AvatarLoading
    @ObservationIgnored private var sessions: [String: HFRSession] = [:]
    @ObservationIgnored private var statuses: [String: AccountSessionStatus] = [:]
    @ObservationIgnored private var restoreTask: Task<Void, Never>?
    /// The last avatar download started by a login (tests await it).
    @ObservationIgnored private(set) var avatarTask: Task<Void, Never>?

    /// Creates the model; nothing is read before `restore()`.
    init(store: any CredentialStore, loginService: any AccountLoggingIn, checker: any SessionChecking, avatars: any AvatarLoading) {
        self.store = store
        self.loginService = loginService
        self.checker = checker
        self.avatars = avatars
    }

    /// The model the app runs with: Keychain store keyed by the bundle identifier, `LoginFlow`, local session check.
    static func live() -> AccountsModel {
        AccountsModel(
            store: KeychainCredentialStore(service: Bundle.main.bundleIdentifier ?? "hfrplus.red.super"),
            loginService: LoginFlow(),
            checker: LocalSessionCheck(),
            avatars: AnonymousAvatarLoader()
        )
    }

    /// The current (main) account.
    var current: AccountRow? { rows.first { $0.isMain } }

    /// The current account's session, for the screens that read the forum as that account; nil when logged out.
    var currentSession: HFRSession? { current.flatMap { sessions[$0.id] } }

    /// The session of an account.
    func session(for id: String) -> HFRSession? { sessions[id] }

    // MARK: - Launch

    /// Reads the store, rebuilds one session per account from its cookies and token, then checks each session.
    /// Runs once; later calls wait for the first one. `retryRestore()` reads again after a store problem.
    func restore() async {
        if let restoreTask { return await restoreTask.value }
        let task = Task { await performRestore() }
        restoreTask = task
        await task.value
    }

    /// Reads the store again (after the device was unlocked, for example).
    func retryRestore() async {
        restoreTask = nil
        await restore()
    }

    /// Erases every stored account; offered only for a corrupted store (LOT-065: never done silently).
    func eraseStoredAccounts() async {
        do {
            try store.removeAll()
        } catch {
            storeProblem = .unavailable(status: (error as? CredentialStoreError).flatMap(Self.keychainStatus) ?? 0)
            return
        }
        await retryRestore()
    }

    private func performRestore() async {
        let book: AccountBook
        do {
            book = try store.load()
        } catch {
            storeProblem = StoreProblem(error as? CredentialStoreError ?? .corrupted)
            rows = []
            sessions = [:]
            hasRestored = true
            return
        }
        storeProblem = nil
        var restored: [String: HFRSession] = [:]
        for account in book.accounts {
            restored[account.pseudo] = sessions[account.pseudo]
                ?? HFRSession(cookies: account.cookies, hashCheck: account.hashCheck)
        }
        sessions = restored
        statuses = statuses.filter { restored[$0.key] != nil }
        for account in book.accounts where statuses[account.pseudo] == nil {
            statuses[account.pseudo] = .checking
        }
        publish(book)
        hasRestored = true
        await checkSessions(book.accounts.map(\.pseudo))
    }

    /// Checks sessions one after the other, so the forum never sees a burst at launch.
    private func checkSessions(_ ids: [String]) async {
        for id in ids {
            guard let session = sessions[id], statuses[id] == .checking else { continue }
            let result = await checker.check(session)
            guard sessions[id] === session, statuses[id] == .checking else { continue }
            switch result {
            case .valid:
                statuses[id] = .valid
                await persistSession(of: id)
            case .expired:
                statuses[id] = .expired
            case .unconfirmed:
                statuses[id] = .restored
            case .failed(let error):
                statuses[id] = .checkFailed(error)
            }
            reloadRows()
        }
    }

    // MARK: - Actions

    /// Logs in and stores the account. A new account becomes the current one (legacy `AccountSessionService.swift:68-75`);
    /// a known account logged in again keeps its place. On failure nothing changes, neither sessions nor store.
    func logIn(pseudo: String, password: String, for target: LoginTarget) async throws(AccountActionError) {
        let session: HFRSession
        let expectedUserKey: String?
        switch target {
        case .newAccount:
            // A fresh session: if the credentials are those of a known account, its session is replaced only
            // once the store has accepted the new cookies.
            session = HFRSession()
            expectedUserKey = nil
        case .existing(let id, _):
            guard let existing = sessions[id] else { throw .unknownAccount }
            session = existing
            expectedUserKey = id
        }
        let result: LoginResult
        do {
            result = try await loginService.logIn(
                pseudo: pseudo, password: password, into: session, expectedUserKey: expectedUserKey
            )
        } catch {
            throw .login(error)
        }
        if case .existing(let id, _) = target {
            // The login already renewed this session in memory; it stays valid even if the store write below fails.
            statuses[id] = .valid
        }
        let account = Account(
            pseudo: result.userKey, displayName: result.displayName,
            cookies: await session.cookies(), hashCheck: await session.hashCheck
        )
        let stored: Account
        do {
            stored = try store.save(account, makeMain: target == .newAccount)
        } catch {
            reloadRows()
            throw .store(error as? CredentialStoreError ?? .corrupted)
        }
        sessions[stored.pseudo] = session
        statuses[stored.pseudo] = .valid
        storeProblem = nil
        reloadRows()
        if let avatarURL = result.avatarURL {
            avatarTask = Task { await self.fetchAvatar(at: avatarURL, for: stored.pseudo) }
        }
    }

    /// Makes an account the current one.
    func select(_ id: String) throws(AccountActionError) {
        do {
            guard try store.setMain(pseudo: id) else { throw AccountActionError.unknownAccount }
        } catch let error as AccountActionError {
            throw error
        } catch {
            throw .store(error as? CredentialStoreError ?? .corrupted)
        }
        reloadRows()
    }

    /// Removes an account from the app: its stored cookies and its session (no server logout, as legacy
    /// `MultisManager.m:125-153`). When it was the current one, the first remaining account becomes current.
    func remove(_ id: String) throws(AccountActionError) {
        do {
            guard try store.deleteAccount(pseudo: id) != nil else { throw AccountActionError.unknownAccount }
        } catch let error as AccountActionError {
            throw error
        } catch {
            throw .store(error as? CredentialStoreError ?? .corrupted)
        }
        sessions[id] = nil
        statuses[id] = nil
        reloadRows()
    }

    /// Writes an account's current cookies and token back to the store, after the forum refreshed them. Skipped
    /// when the session lost its identity: a logged-out jar never replaces stored cookies.
    func persistSession(of id: String) async {
        guard let session = sessions[id], await session.isLoggedIn() else { return }
        let cookies = await session.cookies()
        let hashCheck = await session.hashCheck
        do {
            try store.update { book in
                guard var account = book.account(matching: id) else { return }
                account.cookies = cookies
                account.hashCheck = hashCheck
                // `add` refreshes in place and refuses cookies whose `md_user` names another pseudo.
                try book.add(account, makeMain: false)
            }
        } catch {
            // The stored cookies stay the previous ones; the session in memory still works, and the next
            // successful check or login writes again.
            return
        }
    }

    // MARK: - Private

    private func fetchAvatar(at url: URL, for id: String) async {
        guard let data = await avatars.avatarData(at: url) else { return }
        do {
            try store.update { book in
                guard var account = book.account(matching: id) else { return }
                account.avatarData = data
                book.replace(account)
            }
        } catch {
            // Avatar is decoration: the list keeps the placeholder.
            return
        }
        reloadRows()
    }

    private func reloadRows() {
        do {
            publish(try store.load())
        } catch {
            storeProblem = StoreProblem(error as? CredentialStoreError ?? .corrupted)
        }
    }

    private func publish(_ book: AccountBook) {
        rows = book.accounts.map { account in
            AccountRow(
                id: account.pseudo, displayName: account.displayName, isMain: account.isMain,
                avatarData: account.avatarData, status: statuses[account.pseudo] ?? .restored
            )
        }
    }

    private static func keychainStatus(_ error: CredentialStoreError) -> Int32? {
        if case .keychain(let status) = error { return status }
        return nil
    }
}
