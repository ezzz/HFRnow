import Foundation
import HFRModels
import HFRNetwork

/// A transport with its own cookie jar, in which a flow runs (a login attempt, a session refresh) before anything
/// reaches the account session.
///
/// `HFRSession` is the real one; tests script the answers and the cookies they set.
protocol SessionJar: HTTPTransport {
    /// Every non-expired cookie of the jar.
    func cookies(now: Date) async -> [StoredCookie]
    /// Value of a usable `md_user` (see `HFRSession.userKey(now:)`).
    func userKey(now: Date) async -> String?
}

extension HFRSession: SessionJar {}
