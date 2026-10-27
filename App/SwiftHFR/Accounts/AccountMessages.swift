import HFRClient
import HFRNetwork
import HFRStorage

/// Why an account action (add, log in again, select, remove) failed.
enum AccountActionError: Error, Sendable, Equatable {
    /// The login itself failed; the session was not changed (LOT-043).
    case login(LoginError)
    /// The login worked but the account store refused to read or write (LOT-065).
    case store(CredentialStoreError)
    /// The account is no longer in the store (removed meanwhile).
    case unknownAccount
    /// The store failed with an error of its storage layer (file system), not a `CredentialStoreError`.
    case storeFailed
}

/// A problem reading the account store at launch, with what the user can do about it.
enum StoreProblem: Sendable, Equatable {
    /// The stored accounts cannot be decoded; only erasing them gets out of it (never done silently, LOT-065).
    case corrupted
    /// A newer app version wrote the accounts; this version neither reads nor overwrites them.
    case newerVersion
    /// The Keychain (with its `OSStatus`) or the storage refused access; retrying may work (device locked).
    case unavailable(status: Int32?)

    /// Maps a store error; an error that is not a `CredentialStoreError` (file system) is `unavailable`.
    init(_ error: any Error) {
        switch error as? CredentialStoreError {
        case .corrupted, .invalidPseudo, .pseudoMismatch: self = .corrupted
        case .unsupportedVersion: self = .newerVersion
        case .keychain(let status): self = .unavailable(status: status)
        case nil: self = .unavailable(status: nil)
        }
    }
}

/// User-facing texts (French, as the legacy app). Messages never include a password, cookie or page content.
enum AccountMessages {
    /// What to tell the user about a failed account action; nil when nothing must be shown (a cancelled login).
    static func message(for error: AccountActionError) -> String? {
        switch error {
        case .login(let error): message(for: error)
        case .store(let error): message(for: error)
        case .unknownAccount: "Ce compte n’est plus enregistré. Ajoutez-le de nouveau."
        case .storeFailed: "L’enregistrement du compte a échoué. Réessayez."
        }
    }

    /// Text for each `LoginError` case; each one says what to do next.
    static func message(for error: LoginError) -> String? {
        switch error {
        case .missingCredentials:
            "Saisissez votre pseudo et votre mot de passe."
        case .invalidCredentials:
            "Pseudo ou mot de passe incorrect. Vérifiez-les puis réessayez."
        case .unrecognizedResponse:
            "Le forum a répondu de façon inattendue (maintenance ou trop de tentatives ?). Réessayez dans quelques minutes."
        case .missingIdentityCookie:
            "Le forum n’a pas ouvert de session. Vérifiez que les cookies ne sont pas bloqués, puis réessayez."
        case .accountMismatch:
            "Ces identifiants ouvrent un autre compte que celui-ci. Pour l’ajouter, utilisez « Ajouter un compte »."
        case .missingHashCheck:
            "La session ouverte par le forum est incomplète. Réessayez."
        case .network(let error):
            message(for: error)
        }
    }

    /// Text for a transport failure; nil for a cancellation, which the user asked for.
    static func message(for error: NetworkError) -> String? {
        switch error {
        case .cancelled:
            nil
        case .offline:
            "Pas de connexion à internet. Vérifiez le réseau puis réessayez."
        case .timedOut:
            "Le forum ne répond pas. Réessayez dans quelques instants."
        case .httpStatus(let code, _):
            "Le forum a renvoyé l’erreur \(code). Réessayez plus tard."
        case .invalidRequest, .invalidResponse, .transport, .unscripted:
            "La connexion au forum a échoué. Réessayez."
        }
    }

    /// Text for a store failure after a successful login or on select/remove.
    static func message(for error: CredentialStoreError) -> String {
        switch error {
        case .corrupted:
            "Les comptes enregistrés sont illisibles. Ouvrez « Comptes » pour les effacer."
        case .unsupportedVersion:
            "Les comptes ont été enregistrés par une version plus récente de l’app. Mettez l’app à jour."
        case .invalidPseudo, .pseudoMismatch:
            "Le forum a renvoyé une session qui ne correspond pas à ce pseudo. Réessayez."
        case .keychain(let status):
            "Le trousseau a refusé l’enregistrement (code \(status)). Réessayez."
        }
    }

    /// Text and action label for a launch-time store problem.
    static func message(for problem: StoreProblem) -> String {
        switch problem {
        case .corrupted:
            "Les comptes enregistrés sont illisibles. Effacez-les, puis ajoutez de nouveau vos comptes."
        case .newerVersion:
            "Les comptes ont été enregistrés par une version plus récente de l’app. Mettez l’app à jour pour les retrouver."
        case .unavailable(let status?):
            "Le trousseau est inaccessible (code \(status)). Déverrouillez l’appareil puis réessayez."
        case .unavailable(nil):
            "Les comptes enregistrés sont inaccessibles. Déverrouillez l’appareil puis réessayez."
        }
    }
}
