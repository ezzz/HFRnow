import Foundation
import HFRModels
import HFRNetwork
import HFRParsing

/// Logs an account in, and only touches its session once HFR has validated the login.
///
/// Legacy deleted every cookie of the shared jar before posting the credentials, so a mistyped password logged the
/// current account out (`LoginService.swift:49`, audit A §4.2). Here each attempt runs in a fresh, empty jar: POST the
/// credentials, require HFR's success page and a usable `md_user`, then read the profile page 5 with the new cookies
/// for `hash_check` and the avatar (`LoginService.swift:48-129`). Only then are the target session's cookies replaced
/// and its `hash_check` set, in one step. Any failure leaves the target session exactly as it was.
public struct LoginFlow: Sendable {
    private let makeJar: @Sendable () -> any LoginJar

    /// Creates the flow; each attempt runs in its own new `HFRSession`.
    public init() {
        self.init(makeJar: { HFRSession() })
    }

    /// Creates the flow with another jar for the attempts (tests).
    init(makeJar: @escaping @Sendable () -> any LoginJar) {
        self.makeJar = makeJar
    }

    /// Logs `pseudo` in and, once validated, installs the new session cookies and `hash_check` in `session`.
    ///
    /// The pseudo is trimmed, as legacy did before logging in (`AccountSessionService.swift:62`); the password is sent
    /// as typed. Pass `expectedUserKey` (the account's `md_user` value, `Account.pseudo`) when logging an existing
    /// account in again: credentials of another account are then refused instead of replacing its cookies.
    /// `expectedUserKey` is compared exactly with the raw cookie value, which HFR URL-encodes (HFR-PROTOCOL §5): pass the
    /// stored `LoginResult.userKey`, never the typed pseudo. The identity must be the same after the profile page,
    /// which sets `md_user` again: `deleted` or absent then throws `missingIdentityCookie`, another value `accountMismatch`.
    /// The whole jar is replaced, so cookies the session held before (multi-quote selections included) are dropped.
    /// - Throws: `LoginError`; the session is unchanged whenever it throws.
    public func login(
        pseudo: String,
        password: String,
        into session: HFRSession,
        expectedUserKey: String? = nil,
        now: Date = Date()
    ) async throws(LoginError) -> LoginResult {
        let pseudo = pseudo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pseudo.isEmpty, !password.isEmpty else { throw .missingCredentials }
        let jar = makeJar()

        let answer = try await send({ try HFREndpoint.login(pseudo: pseudo, password: password) }, through: jar)
        switch LoginResponse.classify(answer.decodedText().text) {
        case .accepted: break
        case .refused: throw .invalidCredentials
        case .unrecognized: throw .unrecognizedResponse
        }
        guard let userKey = await jar.userKey(now: now) else { throw .missingIdentityCookie }
        if let expectedUserKey, expectedUserKey != userKey { throw .accountMismatch }

        // Page 5 is read with the new cookies: a non-empty token proves they work (logged-out pages print it empty).
        let profile = try await send({ try HFREndpoint.editProfile(page: .hashAndAvatar) }, through: jar)
        let page: ProfileEditPage
        do {
            page = try ProfileEditPageParser.parse(profile.decodedText().text)
        } catch {
            throw .missingHashCheck
        }
        // The profile page sets `md_user` and `md_passs` again (`R55-p5`): read the jar only now, and check that the
        // identity it ends with is still the one validated above (and so the expected one).
        let cookies = await jar.cookies(now: now)
        guard let finalUserKey = await jar.userKey(now: now) else { throw .missingIdentityCookie }
        guard finalUserKey == userKey else { throw .accountMismatch }
        try await session.adoptLogin(cookies: cookies, hashCheck: page.hashCheck, now: now)
        return LoginResult(userKey: userKey, displayName: pseudo, avatarURL: page.avatarURL)
    }

    private func send(_ build: () throws -> HTTPRequest, through jar: any LoginJar) async throws(LoginError) -> HTTPResponse {
        let request: HTTPRequest
        do {
            request = try build()
        } catch let error as NetworkError {
            throw .network(error)
        } catch {
            throw .network(.invalidRequest(reason: "request could not be built"))
        }
        if Task.isCancelled { throw .network(.cancelled) }
        do {
            return try await jar.send(request)
        } catch {
            throw .network(error)
        }
    }
}
