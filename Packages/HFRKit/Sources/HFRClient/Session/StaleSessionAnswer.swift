import Foundation
import HFRModels
import HFRNetwork
import HFRParsing

/// HFR's answer to an account jar whose `md_passs` it refuses, as flows that send with the account's cookies meet it
/// (#383): `SessionRefreshFlow` on profile page 1 (`R70c`), `MPUnreadPoll` on the home page (`R70a`); the LOT-092 check
/// on the followed-topics page (`R70b`) is the next caller.
enum StaleSessionAnswer {
    /// The cookies HFR checks: the identity and the password it refused (`R70a`–`R70d` keep `md_id`, change `md_passs`).
    static let credentialNames: Set<String> = [HFRSession.identityCookieName, "md_passs"]

    /// True when `response` is the stale-session page served for `request` itself: a 2xx at exactly the requested URL
    /// (no redirect followed) with the `.hop` sentence and the `unlog.php` refresh target (`StaleSessionNoticeParser`).
    /// Every other answer is false, so a caller keeps reading it as it did before.
    static func matches(_ response: HTTPResponse, requestedURL: URL) -> Bool {
        guard (200..<300).contains(response.statusCode), response.url == requestedURL else { return false }
        let html = response.decodedText().text
        return (try? StaleSessionNoticeParser.isStaleSessionNotice(html: html, requestURL: response.url)) == true
    }

    /// The credential cookies among `cookies`, the part of a jar the stale-session page is about.
    static func credentials(in cookies: [StoredCookie]) -> Set<StoredCookie> {
        Set(cookies.filter { credentialNames.contains($0.name) })
    }
}

extension HFRSession {
    /// Reports HFR's stale-session page answered to `seed`'s cookies as an expiry of this session, in one actor turn.
    ///
    /// The page describes the cookies the request carried, not the session as it is now: it is `expired` only while the
    /// session still has the seed's identity, login generation and credential cookies (`md_user`, `md_passs`). A login
    /// adopted meanwhile, a logout, or a request that changed those cookies makes it `unconfirmed(.sessionChanged)`, so a
    /// fresher session is never reported expired. Writes nothing either way: `expired` describes, the app decides.
    /// Checks cancellation on the actor, as `adoptRefresh` does.
    func confirmStaleSession(seed: RefreshSeed, now: Date) throws(NetworkError) -> SessionHealth {
        if Task.isCancelled { throw .cancelled }
        guard
            let identity = seed.identity, userKey(now: now) == identity, loginGeneration == seed.loginGeneration,
            StaleSessionAnswer.credentials(in: cookies(now: now)) == StaleSessionAnswer.credentials(in: seed.cookies)
        else { return .unconfirmed(.sessionChanged) }
        return .expired(.credentialsRefused)
    }
}
