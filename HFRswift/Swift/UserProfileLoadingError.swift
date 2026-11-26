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
    /// The forum refused the request although the session cookies were sent (expired session, most likely).
    case accessDenied
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
        case .httpStatus(let statusCode):
            return "Le forum a répondu avec une erreur \(statusCode)."
        }
    }
}
