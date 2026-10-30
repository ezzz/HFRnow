import HFRClient
import HFRNetwork

/// User-facing texts of the composer (French). Each one says whether anything was posted and what to do next; HFR's own
/// sentence is shown when it gave one (a refusal, a missing form). Never the user's text, a token or a cookie.
enum ComposerMessages {
    /// What to tell the user about a failed reply. The text is always kept in the composer and its draft.
    static func message(for error: PostingError) -> String {
        switch error {
        case .formUnavailable(let message):
            message ?? "Le forum ne propose pas de répondre à ce sujet (sujet fermé ?). Rien n’a été envoyé."
        case .notLoggedIn:
            "Votre session a expiré : rien n’a été envoyé. Reconnectez-vous depuis le menu Comptes, puis renvoyez la réponse."
        case .rejected(let message):
            message ?? "Le forum a refusé la réponse : rien n’a été envoyé. Réessayez."
        case .unconfirmed(let uncertainty):
            unconfirmed(uncertainty)
        case .network(let error):
            network(error)
        case .emptyInput:
            "Écrivez un message avant d’envoyer."
        case .unsupportedCharacters(_, let characters):
            unsupported(characters)
        case .invalidFormURL, .missingAction, .unsupportedForm, .formMismatch, .lineBreak, .tooLong, .unknownSubcategory,
             .subjectNotEditable, .optionNotOffered, .deleteNotOffered, .wholeTopicDeletionNotConfirmed:
            "Le formulaire de réponse du forum n’est pas pris en charge : rien n’a été envoyé. Actualisez le sujet puis réessayez."
        }
    }

    /// Characters outside the Basic Multilingual Plane: HFR cuts the message at the first one and still answers success
    /// (decision Q-3, `W12`), so they are refused before anything is sent.
    static func unsupported(_ characters: [Character]) -> String {
        let list = characters.map(String.init).joined(separator: " ")
        return "Le forum ne peut pas enregistrer ces caractères et couperait le message au premier : \(list). "
            + "Retirez-les puis envoyez."
    }

    /// The reply may have been posted: the user checks the topic before sending again (never resent on its own).
    private static func unconfirmed(_ uncertainty: PostingUncertainty) -> String {
        let base = "Le forum n’a pas confirmé l’envoi : votre réponse a peut-être été postée. "
            + "Vérifiez le sujet avant de renvoyer ; le texte est gardé."
        switch uncertainty {
        case .unrecognizedAnswer(let message?), .unexpectedConfirmation(let message?):
            return base + " Réponse du forum : « \(message) »"
        case .transport, .unrecognizedAnswer(nil), .unexpectedConfirmation(nil):
            return base
        }
    }

    /// The form could not be fetched, or the POST could not leave: nothing was posted.
    private static func network(_ error: NetworkError) -> String {
        switch error {
        case .offline:
            "Pas de connexion à internet : rien n’a été envoyé. Réessayez une fois connecté."
        case .timedOut:
            "Le forum ne répond pas : rien n’a été envoyé. Réessayez dans quelques instants."
        case .cancelled:
            "Envoi annulé : rien n’a été envoyé."
        case .httpStatus(let code, _):
            "Le forum a renvoyé l’erreur \(code) : rien n’a été envoyé. Réessayez plus tard."
        case .invalidRequest, .invalidResponse, .transport, .unscripted:
            "La connexion au forum a échoué : rien n’a été envoyé. Réessayez."
        }
    }
}
