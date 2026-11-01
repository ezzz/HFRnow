import Foundation
import HFRClient
import HFRModels
import HFRNetwork
import HFRStorage
import Observation
import UIKit

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
    /// True once `restore()` has read the store; until then the screens show no logged-out state.
    private(set) var hasRestored = false
    /// True while a restore (read and session checks) runs; a retry then waits for it instead of starting another.
    private(set) var isRestoring = false
    /// True while a quiet re-check (`recheckUnconfirmedSessions`) runs; no screen shows it.
    @ObservationIgnored private(set) var isRechecking = false
    /// Changes whenever `currentSession` becomes another object (select, remove, logout, a known current account
    /// added again). Screens built on the current session are rebuilt on it, never on `current?.id`, which does not
    /// change when the current account's session is replaced.
    private(set) var currentSessionGeneration = 0

    @ObservationIgnored private let store: any CredentialStore
    @ObservationIgnored private let loginService: any AccountLoggingIn
    @ObservationIgnored private let checker: any SessionChecking
    @ObservationIgnored private let avatars: any AvatarLoading
    @ObservationIgnored private var sessions: [String: HFRSession] = [:]
    @ObservationIgnored private var statuses: [String: AccountSessionStatus] = [:]
    /// Advanced by every login saved for an account: a session write-back whose jar was read before it is stale,
    /// even when the login renewed the same `HFRSession` object.
    @ObservationIgnored private var loginSaves: [String: Int] = [:]
    @ObservationIgnored private var restoreTask: Task<Void, Never>?
    @ObservationIgnored private var currentSessionID: ObjectIdentifier?
    /// When the last forum check of the sessions (launch or re-check) ended; nil until one has.
    @ObservationIgnored private var lastCheckEnd: Date?
    /// Cookie jar for browsing logged out; never holds an account's cookies.
    @ObservationIgnored private let loggedOutSession = HFRSession()
    /// Decoded avatars by account, so views never decode image bytes while rendering (LESSONS 49).
    @ObservationIgnored private var avatarImages: [String: (data: Data, image: UIImage)] = [:]
    /// The last avatar download started by a login (tests await it).
    @ObservationIgnored private(set) var avatarTask: Task<Void, Never>?
    /// Test seam: runs in `persistSession` after the jar is read and before the store is written.
    @ObservationIgnored var beforePersistWrite: (@MainActor () async -> Void)?

    /// Creates the model; nothing is read before `restore()`.
    init(store: any CredentialStore, loginService: any AccountLoggingIn, checker: any SessionChecking, avatars: any AvatarLoading) {
        self.store = store
        self.loginService = loginService
        self.checker = checker
        self.avatars = avatars
    }

    /// The model the app runs with: Keychain store keyed by the bundle identifier, `LoginFlow`, the forum session check
    /// (LOT-044).
    static func live() -> AccountsModel {
        AccountsModel(
            // An app bundle always has an identifier; the fallback is the project's own (LOT-080), so the item's
            // service never depends on it being missing.
            store: KeychainCredentialStore(service: Bundle.main.bundleIdentifier ?? "hfrplus.red.super"),
            loginService: LoginFlow(),
            checker: ForumSessionCheck(),
            avatars: AnonymousAvatarLoader()
        )
    }

    /// The current (main) account.
    var current: AccountRow? { rows.first { $0.isMain } }

    /// The current account's session, for the screens that read the forum as that account; nil when logged out.
    var currentSession: HFRSession? { current.flatMap { sessions[$0.id] } }

    /// The session the forum screens use: the current account's, or one logged-out session kept for the whole run.
    var forumSession: HFRSession { currentSession ?? loggedOutSession }

    /// The session of an account.
    func session(for id: String) -> HFRSession? { sessions[id] }

    // MARK: - Launch

    /// Reads the store, rebuilds one session per account from its cookies and token, then checks each session.
    /// Runs once; later calls wait for the first one. `retryRestore()` reads again after a store problem.
    func restore() async {
        if let restoreTask { return await restoreTask.value }
        isRestoring = true
        let task = Task {
            await performRestore()
            isRestoring = false
        }
        restoreTask = task
        await task.value
    }

    /// Reads the store again (after the device was unlocked, for example). While a restore runs, waits for it
    /// instead: two restores at once would check every session twice.
    func retryRestore() async {
        if isRestoring, let restoreTask { return await restoreTask.value }
        restoreTask = nil
        await restore()
    }

    /// Erases every stored account; offered only for a corrupted store (LOT-065: never done silently).
    func eraseStoredAccounts() async {
        do {
            try store.removeAll()
        } catch {
            storeProblem = StoreProblem(error)
            return
        }
        await retryRestore()
    }

    private func performRestore() async {
        let book: AccountBook
        do {
            book = try store.load()
        } catch {
            storeProblem = StoreProblem(error)
            rows = []
            sessions = [:]
            noteCurrentSession()
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
        // A retry after a failed write: sessions already confirmed are written again, or their refreshed cookies
        // would stay unsaved until the next check.
        for account in book.accounts where statuses[account.pseudo] == .valid {
            await persistSession(of: account.pseudo)
        }
        await checkSessions(book.accounts.map(\.pseudo)) { $0 == .checking }
        lastCheckEnd = Date()
    }

    /// Shortest delay between the end of a check and a quiet re-check: the app coming back to the foreground several
    /// times a minute must not send a request each time.
    static let recheckInterval: TimeInterval = 5 * 60

    /// Checks again, quietly, the sessions the forum did not confirm (`restored` after an unknown page, `checkFailed`
    /// after a network error), when the app comes back to the foreground. Sessions already `valid` or `expired` are left
    /// alone; the rows keep their status until a result arrives, and a check that confirms nothing changes nothing.
    /// Skipped while another re-check or a restore runs (its own check may already have marked a session `checkFailed`
    /// and still be waiting on the next account), and until `recheckInterval` has passed since the last check.
    func recheckUnconfirmedSessions(now: Date = Date()) async {
        guard !isRechecking, !isRestoring else { return }
        if let lastCheckEnd, now.timeIntervalSince(lastCheckEnd) < Self.recheckInterval { return }
        let ids = rows.map(\.id).filter { Self.isUnconfirmed(statuses[$0]) }
        guard !ids.isEmpty else { return }
        isRechecking = true
        await checkSessions(ids, when: Self.isUnconfirmed)
        lastCheckEnd = Date()
        isRechecking = false
    }

    private static func isUnconfirmed(_ status: AccountSessionStatus?) -> Bool {
        switch status {
        case .restored, .checkFailed: true
        case .checking, .valid, .expired, nil: false
        }
    }

    /// Checks sessions one after the other, so the forum never sees a burst. Only accounts whose status passes
    /// `eligible` are checked, and a result is applied only if the account still has the same session and status: a
    /// login or a removal that landed during the check wins.
    private func checkSessions(_ ids: [String], when eligible: (AccountSessionStatus?) -> Bool) async {
        for id in ids {
            guard let session = sessions[id], eligible(statuses[id]) else { continue }
            let before = statuses[id]
            let result = await checker.check(session)
            guard sessions[id] === session, statuses[id] == before else { continue }
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
        let account = Account(
            pseudo: result.userKey, displayName: result.displayName,
            cookies: await session.cookies(), hashCheck: await session.hashCheck
        )
        // From here to the save there is no suspension point, so these checks still hold when the store is written.
        if case .existing(let id, _) = target {
            // Removed while the login ran (or while the jar was read above): saving now would bring the account back.
            guard sessions[id] === session else { throw .unknownAccount }
            // The login already renewed this session in memory; it stays valid even if the store write below fails.
            statuses[id] = .valid
        }
        // A new account whose sheet was dismissed meanwhile is not added. A re-login is saved even then: its session
        // is already renewed in memory (LOT-043), and the store must hold what the session holds.
        if target == .newAccount, Task.isCancelled { throw .login(.network(.cancelled)) }
        let stored: Account
        do {
            stored = try store.save(account, makeMain: target == .newAccount)
        } catch {
            reloadRows()
            throw Self.actionError(error)
        }
        loginSaves[stored.pseudo, default: 0] += 1
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
            throw Self.actionError(error)
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
            throw Self.actionError(error)
        }
        sessions[id] = nil
        statuses[id] = nil
        reloadRows()
    }

    /// Writes an account's current cookies and token back to the store, after the forum refreshed them. Skipped
    /// when the session lost its identity: a logged-out jar never replaces stored cookies. A failed write keeps the
    /// previous cookies and is reported as a store problem (LESSONS 8); the session in memory keeps working.
    func persistSession(of id: String) async {
        guard let session = sessions[id] else { return }
        let saves = loginSaves[id, default: 0]
        guard await session.isLoggedIn() else { return }
        let cookies = await session.cookies()
        let hashCheck = await session.hashCheck
        if let beforePersistWrite { await beforePersistWrite() }
        // Replaced (a new login of the same pseudo) or removed while the jar was read: its cookies must not overwrite
        // what the store holds now. Nor if a login was saved meanwhile: a re-login renews this same session, so the
        // jar may have been read before it, and the store already holds the login. No suspension point follows.
        guard sessions[id] === session, loginSaves[id, default: 0] == saves else { return }
        do {
            try store.update { book in
                guard var account = book.account(matching: id) else { return }
                account.cookies = cookies
                account.hashCheck = hashCheck
                // `add` refreshes in place and refuses cookies whose `md_user` names another pseudo.
                try book.add(account, makeMain: false)
            }
        } catch CredentialStoreError.pseudoMismatch, CredentialStoreError.invalidPseudo {
            // The jar names another pseudo than the account: nothing is written and the store is intact, so this is
            // not a store problem. The screens must not keep using a jar of another identity: the session is rebuilt
            // from what is stored, and stays unconfirmed.
            restoreStoredSession(of: id)
        } catch {
            storeProblem = StoreProblem(error)
        }
    }
}

// MARK: - Private

extension AccountsModel {

    private func restoreStoredSession(of id: String) {
        do {
            guard let account = try store.load().account(matching: id) else { return }
            sessions[account.pseudo] = HFRSession(cookies: account.cookies, hashCheck: account.hashCheck)
            statuses[account.pseudo] = .restored
            reloadRows()
        } catch {
            storeProblem = StoreProblem(error)
        }
    }

    private func fetchAvatar(at url: URL, for id: String) async {
        // Decoded once here: bytes that are not an image are never stored.
        guard let data = await avatars.avatarData(at: url), let image = UIImage(data: data) else { return }
        avatarImages[id] = (data, image)
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
            storeProblem = StoreProblem(error)
        }
    }

    private func publish(_ book: AccountBook) {
        rows = book.accounts.map { account in
            AccountRow(
                id: account.pseudo, displayName: account.displayName, isMain: account.isMain,
                avatar: avatar(for: account), status: statuses[account.pseudo] ?? .restored
            )
        }
        noteCurrentSession()
    }

    /// Bumps `currentSessionGeneration` when the current session is another object than last time.
    private func noteCurrentSession() {
        let identity = currentSession.map(ObjectIdentifier.init)
        guard identity != currentSessionID else { return }
        currentSessionID = identity
        currentSessionGeneration += 1
    }

    /// The decoded avatar of an account, decoding only bytes not seen before.
    private func avatar(for account: Account) -> UIImage? {
        guard let data = account.avatarData else {
            avatarImages[account.pseudo] = nil
            return nil
        }
        if let cached = avatarImages[account.pseudo], cached.data == data { return cached.image }
        guard let image = UIImage(data: data) else { return nil }
        avatarImages[account.pseudo] = (data, image)
        return image
    }

    private static func actionError(_ error: any Error) -> AccountActionError {
        (error as? CredentialStoreError).map(AccountActionError.store) ?? .storeFailed
    }
}
