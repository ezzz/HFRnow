import Foundation
import HFRModels
import HFRNetwork

/// A transport with its own cookie jar, in which one login attempt runs before anything reaches the account session.
///
/// `HFRSession` is the real one; tests script the answers and the cookies they set.
protocol LoginJar: HTTPTransport {
    /// Every non-expired cookie of the jar.
    func cookies(now: Date) async -> [StoredCookie]
    /// Value of a usable `md_user` (see `HFRSession.userKey(now:)`).
    func userKey(now: Date) async -> String?
}

extension HFRSession: LoginJar {}

extension HFRSession {
    /// Installs a validated login in one actor turn, so no request of this session sees the new cookies with the old
    /// `hash_check` or the reverse. Checks cancellation on the actor itself: a task cancelled while hopping here must
    /// not change the session, even when HFR already accepted the login.
    func adoptLogin(cookies: [StoredCookie], hashCheck: String, now: Date) throws(LoginError) {
        if Task.isCancelled { throw .network(.cancelled) }
        replaceCookies(with: cookies, now: now)
        updateHashCheck(hashCheck)
    }
}
