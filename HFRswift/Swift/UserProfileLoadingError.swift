//
//  UserProfileLoadingError.swift
//  HFRswift
//
//  Errors shown by the profile sheet when a member profile cannot be loaded.
//

import Foundation

enum UserProfileLoadingError: LocalizedError, Equatable {
    case invalidProfile
    /// No logged-in account: the forum only shows profiles to members.
    case loginRequired
    /// The forum refused the request although the full session was sent (expired session, most likely).
    case accessDenied
    /// The forum refused the request and the session lacks `md_id`, which the forum sets at login only:
    /// the account must be logged in again (#1349).
    case reloginRequired
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidProfile:
            return "Profil impossible à lire."
        case .loginRequired:
            return "Le forum réserve les profils aux membres connectés. Connectez-vous à un compte puis réessayez."
        case .accessDenied:
            return "Le forum a refusé l'accès au profil. "
                + "Votre session a peut-être expiré : reconnectez-vous puis réessayez."
        case .reloginRequired:
            return "Le forum demande désormais une nouvelle connexion pour afficher les profils. "
                + "Supprimez puis ajoutez de nouveau votre compte dans Comptes."
        case .httpStatus(let statusCode):
            return "Le forum a répondu avec une erreur \(statusCode)."
        }
    }
}
