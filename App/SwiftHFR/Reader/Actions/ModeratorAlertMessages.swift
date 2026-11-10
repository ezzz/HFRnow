import HFRClient
import HFRNetwork

/// User-facing texts of the moderator alert (French, LOT-135). Each says whether anything was sent; HFR's own sentence is
/// shown when it gave one. Never the reason, a token or a cookie.
enum ModeratorAlertMessages {
    /// The alert page could not be used: nothing was sent.
    static func prepare(_ error: ModeratorAlertError) -> String {
        switch error {
        case .formUnavailable(let message?):
            message
        case .formUnavailable(nil):
            "Le forum ne propose pas d’alerter les modérateurs sur ce message. Rien n’a été envoyé."
        case .network(let failure):
            network(failure)
        default:
            closed(error)
        }
    }

    /// What the sheet does after a failed send: keep the reason for another try (nothing was sent and the form still
    /// holds), or close because the form is no longer usable or the alert may have left.
    enum SubmitFailure: Equatable {
        /// Nothing was sent; the sheet stays open with the reason.
        case keep(String)
        /// Nothing was sent, but this form cannot be sent any more.
        case close(String)
        /// The alert may have reached the moderators: never offered again.
        case unconfirmed(String)
    }

    /// How the sheet reacts to `error` from a send.
    static func submit(_ error: ModeratorAlertError) -> SubmitFailure {
        switch error {
        case .emptyReason:
            .keep("Décrivez le problème avant d’envoyer.")
        case .unsupportedCharacters(let characters):
            .keep(
                "Le forum ne peut pas enregistrer ces caractères : \(characters.map(String.init).joined(separator: " ")). "
                    + "Retirez-les puis envoyez."
            )
        case .rejected(let message):
            .keep(message ?? "Le forum a refusé l’alerte : rien n’a été envoyé.")
        case .network(let failure):
            .keep(network(failure))
        case .unconfirmed(let uncertainty):
            .unconfirmed(unconfirmed(uncertainty))
        case .notLoggedIn, .sessionChanged, .invalidLink, .formUnavailable, .unsupportedForm:
            .close(closed(error))
        }
    }

    /// The form is no longer usable: nothing was sent, and what to do.
    private static func closed(_ error: ModeratorAlertError) -> String {
        switch error {
        case .notLoggedIn:
            "Votre session a expiré : rien n’a été envoyé. Reconnectez-vous depuis le menu Comptes, puis alertez à nouveau."
        case .sessionChanged:
            "Le compte connecté a changé depuis l’ouverture de l’alerte : rien n’a été envoyé. Alertez à nouveau."
        case .invalidLink:
            "Le lien d’alerte de ce message ne mène pas au forum : rien n’a été envoyé."
        case .formUnavailable(let message?):
            message
        default:
            "Le formulaire d’alerte du forum n’est pas pris en charge : rien n’a été envoyé. Actualisez le sujet puis réessayez."
        }
    }

    /// The alert may have left: say so, never offer to send it again.
    private static func unconfirmed(_ uncertainty: PostingUncertainty) -> String {
        let base = "Le forum n’a pas confirmé l’alerte : elle a peut-être été transmise aux modérateurs, "
            + "elle n’est donc pas renvoyée."
        switch uncertainty {
        case .unrecognizedAnswer(let message?), .unexpectedConfirmation(let message?):
            return base + " Réponse du forum : « \(message) »"
        case .unrecognizedAnswer(nil), .unexpectedConfirmation(nil), .transport:
            return base
        }
    }

    private static func network(_ error: NetworkError) -> String {
        switch error {
        case .offline:
            "Pas de connexion à internet : rien n’a été envoyé. Réessayez une fois connecté."
        case .timedOut:
            "Le forum ne répond pas : rien n’a été envoyé. Réessayez dans quelques instants."
        case .cancelled:
            "Alerte annulée : rien n’a été envoyé."
        case .httpStatus(let code, _):
            "Le forum a renvoyé l’erreur \(code) : rien n’a été envoyé. Réessayez plus tard."
        case .invalidRequest, .invalidResponse, .transport, .unscripted:
            "La connexion au forum a échoué : rien n’a été envoyé. Réessayez."
        }
    }
}
