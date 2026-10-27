/// How HFR answered the login POST, read from the page text (the HTTP status is 200 either way, HFR-PROTOCOL §5).
enum LoginResponse: Equatable {
    /// "Vérification de votre identification..." with a refresh to `login_redirection.php` (`W03`, `W01b`).
    case accepted
    /// The `.hop` refusal "Votre mot de passe ou nom d'utilisateur n'est pas valide" with a refresh to `/` (`W01`).
    case refused
    /// Anything else.
    case unrecognized

    /// Legacy success test: the answer mentions `login_redirection.php` (`LoginService.swift:72`).
    static let successMarker = "login_redirection.php"
    /// The refusal sentence of `W01`; legacy did not look for it and called every other answer a refusal.
    static let refusalText = "Votre mot de passe ou nom d'utilisateur n'est pas valide"

    /// Classifies the decoded answer. The success marker wins, as in legacy; a plain substring is enough because the
    /// flow also requires the `md_user` cookie and a logged-in profile page before it trusts the login.
    static func classify(_ text: String) -> LoginResponse {
        if text.contains(successMarker) { return .accepted }
        if text.contains(refusalText) { return .refused }
        return .unrecognized
    }
}
