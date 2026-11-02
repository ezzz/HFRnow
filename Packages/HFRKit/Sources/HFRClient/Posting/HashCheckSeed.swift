import Foundation

/// The session's identity and token as a request left, read in one actor turn (issue #308).
///
/// The posting-side counterpart of `RefreshSeed` (`Session/RefreshUpdate.swift`), which also carries the cookies a
/// refresh probe starts from; both feed the same compare-and-set rule.
struct HashCheckSeed: Sendable, Equatable {
    /// Usable `md_user` value, nil when the session was logged out.
    let identity: String?
    /// The token the session held.
    let hashCheck: String?
    /// The session's login generation: a re-login of the same account with the same token moves it too (#340).
    let loginGeneration: Int
}

extension PostingSession {
    /// Identity and token in one actor turn, taken before a request whose page carries a token.
    func hashCheckSeed(now: Date = Date()) -> HashCheckSeed {
        HashCheckSeed(identity: userKey(now: now), hashCheck: hashCheck, loginGeneration: loginGeneration)
    }

    /// Records `token`, read on a page requested after `seed` was taken, only when the session still holds `seed`'s
    /// identity, token and login generation; returns whether it was recorded.
    ///
    /// A login adopted while the request was in flight (`adoptLogin`, or a refresh's `adoptRefresh`) installed a token
    /// read with the new cookies: the page's token belongs to the cookies the request was sent with, so writing it would
    /// make the next POST fail with HFR's bad-token answer (`W17b`). Same compare-and-set rule as `adoptRefresh`.
    @discardableResult
    func updateHashCheck(_ token: String, since seed: HashCheckSeed, now: Date = Date()) -> Bool {
        guard hashCheckSeed(now: now) == seed else { return false }
        updateHashCheck(token)
        return true
    }
}
