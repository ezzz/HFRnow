import HFRModels
import HFRNetwork

/// Why a list could not be loaded, in terms the screen can act on (retry, wait, sign in).
enum ListLoadError: Error, Equatable, Sendable {
    /// No connection.
    case offline
    /// The server did not answer in time.
    case timedOut
    /// The server answered with an error status.
    case server(status: Int)
    /// HFR is in maintenance; carries HFR's message.
    case maintenance(String)
    /// The page asks for a login the session does not have; carries HFR's message.
    case notAuthenticated(String)
    /// The page does not look like the expected list; retrying may help, the page may also have changed.
    case unreadable
    /// The load was superseded or cancelled: not shown to the user.
    case cancelled
    /// Any other transport failure.
    case other

    /// Maps a transport failure.
    init(_ error: NetworkError) {
        switch error {
        case .offline: self = .offline
        case .timedOut: self = .timedOut
        case .cancelled: self = .cancelled
        case .httpStatus(let code, _): self = .server(status: code)
        case .invalidRequest, .invalidResponse, .transport, .unscripted: self = .other
        }
    }

    /// Maps a parser failure.
    init(_ failure: ListPageFailure) {
        switch failure {
        case .maintenance(let message): self = .maintenance(message)
        case .notAuthenticated(let message): self = .notAuthenticated(message)
        case .malformed: self = .unreadable
        }
    }

    /// Short title of the failure.
    var title: String {
        switch self {
        case .offline: "Pas de connexion"
        case .timedOut: "Le forum ne répond pas"
        case .server: "Erreur du forum"
        case .maintenance: "Forum en maintenance"
        case .notAuthenticated: "Connexion requise"
        case .unreadable: "Page illisible"
        case .cancelled, .other: "Chargement impossible"
        }
    }

    /// One-line explanation; never contains a URL, a cookie or a token.
    var detail: String {
        switch self {
        case .offline: "Vérifiez votre connexion puis réessayez."
        case .timedOut: "Réessayez dans un instant."
        case .server(let status): "Le serveur a répondu avec le code \(status)."
        case .maintenance(let message), .notAuthenticated(let message): message
        case .unreadable: "HFR a renvoyé une page inattendue."
        case .cancelled, .other: "Réessayez."
        }
    }
}
