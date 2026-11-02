import HFRClient
import HFRNetwork

/// User-facing texts of the composer (French). Each one says whether anything was posted and what to do next; HFR's own
/// sentence is shown when it gave one (a refusal, a missing form). Never the user's text, a token or a cookie.
enum ComposerMessages {
    /// What to tell the user about a failed reply, or a failed new private message when `newMessage` is set. The text is
    /// always kept in the composer and its draft.
    static func message(for error: PostingError, newMessage: Bool = false) -> String {
        let what = newMessage ? "le message" : "la réponse"
        switch error {
        case .formUnavailable(let message):
            return message ?? (newMessage
                ? "Le forum ne propose pas d’écrire ce message privé. Rien n’a été envoyé."
                : "Le forum ne propose pas de répondre à ce sujet (sujet fermé ?). Rien n’a été envoyé.")
        case .notLoggedIn:
            return "Votre session a expiré : rien n’a été envoyé. Reconnectez-vous depuis le menu Comptes, puis renvoyez \(what)."
        case .sessionChanged:
            return "Le compte connecté a changé depuis l’ouverture du formulaire : rien n’a été envoyé. Renvoyez \(what)."
        case .rejected(let message):
            return message ?? "Le forum a refusé \(what) : rien n’a été envoyé. Réessayez."
        case .unconfirmed(let uncertainty):
            return unconfirmed(uncertainty, newMessage: newMessage)
        case .network(let error):
            return network(error)
        case .emptyInput, .lineBreak, .tooLong:
            return field(error)
        case .unsupportedCharacters(_, let characters):
            return unsupported(characters)
        case .invalidFormURL, .missingAction, .unsupportedForm, .formMismatch, .unknownSubcategory, .subjectNotEditable,
             .optionNotOffered, .deleteNotOffered, .wholeTopicDeletionNotConfirmed:
            return newMessage
                ? "Le formulaire de message privé du forum n’est pas pris en charge : rien n’a été envoyé. Réessayez plus tard."
                : "Le formulaire de réponse du forum n’est pas pris en charge : rien n’a été envoyé. "
                    + "Actualisez le sujet puis réessayez."
        }
    }

    /// A field the engine refused before anything was sent: empty, on several lines, or longer than the form allows.
    private static func field(_ error: PostingError) -> String {
        switch error {
        case .emptyInput(.text): "Écrivez un message avant d’envoyer."
        case .emptyInput(.subject): "Indiquez un sujet avant d’envoyer."
        case .emptyInput(.recipient): "Indiquez le pseudo du destinataire avant d’envoyer."
        case .lineBreak(let input): "\(name(of: input)) doit tenir sur une ligne : rien n’a été envoyé."
        case .tooLong(let input, let maximum):
            "\(name(of: input)) dépasse \(maximum) caractères : raccourcissez-le. Rien n’a été envoyé."
        default: "Rien n’a été envoyé."
        }
    }

    private static func name(of input: PostingInput) -> String {
        switch input {
        case .text: "Le message"
        case .subject: "Le sujet"
        case .recipient: "Le destinataire"
        }
    }

    /// Characters outside the Basic Multilingual Plane: HFR cuts the message at the first one and still answers success
    /// (decision Q-3, `W12`), so they are refused before anything is sent.
    static func unsupported(_ characters: [Character]) -> String {
        let list = characters.map(String.init).joined(separator: " ")
        return "Le forum ne peut pas enregistrer ces caractères et couperait le message au premier : \(list). "
            + "Retirez-les puis envoyez."
    }

    /// The write may have been posted: the user checks the topic, or the private messages, before sending again (never
    /// resent on its own).
    private static func unconfirmed(_ uncertainty: PostingUncertainty, newMessage: Bool) -> String {
        let base = newMessage
            ? "Le forum n’a pas confirmé l’envoi : votre message a peut-être été envoyé. "
                + "Vérifiez vos messages privés avant de renvoyer ; le texte est gardé."
            : "Le forum n’a pas confirmé l’envoi : votre réponse a peut-être été postée. "
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
