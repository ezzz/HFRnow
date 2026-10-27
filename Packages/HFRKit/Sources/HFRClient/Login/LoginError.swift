import HFRNetwork

/// Why a login did not complete. In every case the target session's cookies and `hash_check` are left untouched.
///
/// No case carries the pseudo, the password or page content: errors end up in logs.
public enum LoginError: Error, Sendable, Equatable {
    /// The pseudo (after trimming) or the password is empty; nothing was sent.
    case missingCredentials
    /// HFR refused the pseudo or the password ("Votre mot de passe ou nom d'utilisateur n'est pas valide", `W01`).
    case invalidCredentials
    /// HFR answered neither its success page nor its refusal page (maintenance, flood protection, a changed site).
    case unrecognizedResponse
    /// HFR showed its success page but set no usable `md_user` cookie.
    case missingIdentityCookie
    /// The credentials logged in another account than the one expected (its `md_user` differs).
    case accountMismatch
    /// The profile page read after the login holds no usable `hash_check`, so the new session cannot post.
    case missingHashCheck
    /// An exchange failed (network, HTTP status, cancellation).
    case network(NetworkError)
}
