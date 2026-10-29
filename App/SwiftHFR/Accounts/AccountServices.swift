import Foundation
import HFRClient
import HFRModels
import HFRNetwork

/// Logs an account in through `HFRClient` (LOT-043); `LoginFlow` in the app, a scripted double in tests.
protocol AccountLoggingIn: Sendable {
    /// Same contract as `LoginFlow.login`: `session` changes only when the login is validated.
    func logIn(
        pseudo: String, password: String, into session: HFRSession, expectedUserKey: String?
    ) async throws(LoginError) -> LoginResult
}

extension LoginFlow: AccountLoggingIn {
    /// Forwards to `login(pseudo:password:into:expectedUserKey:now:)` at the current date.
    func logIn(
        pseudo: String, password: String, into session: HFRSession, expectedUserKey: String?
    ) async throws(LoginError) -> LoginResult {
        try await login(pseudo: pseudo, password: password, into: session, expectedUserKey: expectedUserKey)
    }
}

/// What a session check learned about a restored account session.
enum SessionCheckResult: Sendable, Equatable {
    /// The session works; its cookies or `hash_check` may have been refreshed and should be persisted.
    case valid
    /// The session holds no usable identity: the account must log in again.
    case expired
    /// Nothing could be concluded; the session is kept as it was.
    case unconfirmed
    /// The check could not reach the forum; the session is kept as it was.
    case failed(NetworkError)
}

/// Checks a restored account session: `ForumSessionCheck` in the app, a scripted double in tests.
protocol SessionChecking: Sendable {
    /// Checks `session` and never clears it.
    func check(_ session: HFRSession) async -> SessionCheckResult
}

/// Runs LOT-044's forum check; `SessionRefreshFlow` in the app, a scripted double in tests (its probe seam is internal
/// to `HFRClient`).
protocol SessionRefreshing: Sendable {
    /// Same contract as `SessionRefreshFlow.refresh`: only `valid` writes to `session`.
    func refresh(_ session: HFRSession, now: Date) async throws(NetworkError) -> SessionHealth
}

extension SessionRefreshFlow: SessionRefreshing {}

/// The forum-backed check (LOT-044): GETs the account's profile page 1 with its cookies, and merges what HFR refreshed
/// only when the page proves the session works. A page that proves nothing, or a failed request, never logs out.
struct ForumSessionCheck: SessionChecking {
    private let refresher: any SessionRefreshing

    /// Creates a check on `refresher` (the live flow by default).
    init(refresher: any SessionRefreshing = SessionRefreshFlow()) {
        self.refresher = refresher
    }

    /// Refreshes `session` now and maps the outcome; never throws, never clears the session.
    func check(_ session: HFRSession) async -> SessionCheckResult {
        do {
            return Self.result(of: try await refresher.refresh(session, now: Date()))
        } catch .cancelled {
            // A cancelled check says nothing about the forum: it is not an unreachable forum.
            return .unconfirmed
        } catch {
            return .failed(error)
        }
    }

    /// `expired` only when the jar itself holds no usable identity (`SessionExpiry`); every `unconfirmed` reason keeps
    /// the session as it was (LOT-044: an unknown page never logs an account out).
    static func result(of health: SessionHealth) -> SessionCheckResult {
        switch health {
        case .valid: .valid
        case .expired: .expired
        case .unconfirmed: .unconfirmed
        }
    }
}

/// Downloads an account's avatar for the account list.
protocol AvatarLoading: Sendable {
    /// The image bytes at `url`, or nil when the URL is not allowed or the download fails.
    func avatarData(at url: URL) async -> Data?
}

/// Fetches avatars without cookies (`AnonymousTransport`, HFR-PROTOCOL §7 E26), from the forum's image host only.
struct AnonymousAvatarLoader: AvatarLoading {
    /// The host profile page 5 points avatars to (`R55-p5u1`, HFR-PROTOCOL §6 "Profile edit pages").
    static let allowedHost = "forum-images.hardware.fr"
    /// Forum avatars are a few KiB; anything far larger is not stored in the Keychain item (LOT-065 edge cases).
    static let maximumBytes = 256 * 1024

    private let transport: any HTTPTransport

    /// Creates a loader on a fresh cookie-less transport.
    init(transport: any HTTPTransport = AnonymousTransport()) {
        self.transport = transport
    }

    /// True for `https://forum-images.hardware.fr/…` on the default port only (LESSONS 37).
    static func isAllowed(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host()?.lowercased() == allowedHost && (url.port == nil || url.port == 443)
    }

    /// True for an `image/…` content type (parameters and case ignored).
    static func isImage(_ contentType: String?) -> Bool {
        contentType?.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("image/") == true
    }

    /// Downloads the avatar; any failure is nil and the list shows the placeholder.
    func avatarData(at url: URL) async -> Data? {
        guard Self.isAllowed(url) else { return nil }
        // Follow no redirect: a redirect could leave the allowed host.
        guard let response = try? await transport.send(.get(url, redirectPolicy: .doNotFollow)),
              response.statusCode == 200, !response.body.isEmpty, response.body.count <= Self.maximumBytes,
              Self.isImage(response.headers["Content-Type"])
        else { return nil }
        return response.body
    }
}
