import Foundation
import HFRModels
import HFRNetwork

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
