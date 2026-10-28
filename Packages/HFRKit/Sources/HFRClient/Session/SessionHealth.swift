/// What a session refresh learned about an account session (`SessionRefreshFlow`).
///
/// Only `valid` writes to the session. The other outcomes write neither cookies nor `hash_check`: a page
/// that proves nothing must never log an account out (LESSONS 44).
public enum SessionHealth: Sendable, Equatable {
    /// HFR served the account's own profile page with its token: refreshed cookies and `hash_check` were merged.
    case valid
    /// The session cannot be authenticated; nothing was sent and nothing changed.
    case expired(SessionExpiry)
    /// HFR's answer proved neither state; the flow wrote nothing.
    case unconfirmed(UnconfirmedSession)
}

/// Why a session is known to be logged out.
///
/// Only rules backed by legacy code or a capture belong here. HFR's answer to stale cookies is not captured yet
/// (LOT-044 spec, pending capture): when it is, its shape becomes a new case.
public enum SessionExpiry: Sendable, Equatable {
    /// The jar holds no usable `md_user`: never logged in, cookie past its expiry, or `deleted` (`HFRSession.userKey`).
    case noIdentityCookie
}

/// Why an answer did not confirm the session.
public enum UnconfirmedSession: Sendable, Equatable {
    /// Not the profile page with a non-empty `hash_check`: another page, a redirect, a `.hop` notice or an empty token.
    case unrecognizedPage
    /// After the answer, the probe no longer held the same usable `md_user` (removed, changed or `deleted`).
    case identityNotConfirmed
    /// The account session changed identity while the refresh ran (logout, another login).
    case sessionChanged
}
