import HFRClient
import HFRNetwork

/// User-facing texts of the poll sheet (French). Each says whether the vote was counted and what to do next; HFR's own
/// sentence is shown when it gave one. Never a token or a cookie.
enum PollMessages {
    /// Shown when HFR confirmed the vote: HFR's sentence, else ours.
    static func confirmed(_ result: PollVoteResult) -> String {
        result.message.isEmpty ? "Votre vote a bien été pris en compte." : result.message
    }

    /// What to tell the user about a vote that did not end with HFR's confirmation. The sheet
    /// reloads the topic when the vote may have been counted (`PollModel`).
    static func message(for error: PollVoteError) -> String {
        switch error {
        case .notVotable:
            "Ce sondage n’accepte plus de vote."
        case .unsupportedPoll:
            "Ce type de sondage n’est pas encore pris en charge : votez depuis le site. Rien n’a été envoyé."
        case .invalidChoice:
            "Choisissez une réponse du sondage. Rien n’a été envoyé."
        case .sessionNotConfirmed, .notLoggedIn:
            "Votre session a expiré : rien n’a été envoyé. Reconnectez-vous depuis le menu Comptes, puis votez."
        case .loginChanged:
            "Le compte connecté a changé : rien n’a été envoyé. Votez à nouveau."
        case .missingToken:
            "La session n’est pas prête : rien n’a été envoyé. Actualisez le sujet puis réessayez."
        case .alreadyVoted:
            "Vous avez déjà voté à ce sondage (ou un de vos pseudos liés)."
        case .rejected(let message):
            message ?? "Le forum a refusé le vote : rien n’a été compté. Actualisez le sujet puis réessayez."
        case .unconfirmed:
            "Le forum n’a pas confirmé le vote : il a peut-être été compté. "
                + "Le sujet est actualisé : regardez le sondage avant de voter à nouveau."
        case .network(let error):
            network(error)
        }
    }

    private static func network(_ error: NetworkError) -> String {
        switch error {
        case .offline:
            "Pas de connexion à internet : rien n’a été envoyé. Réessayez une fois connecté."
        case .timedOut:
            "Le forum ne répond pas : rien n’a été envoyé. Réessayez dans quelques instants."
        case .cancelled:
            "Vote annulé : rien n’a été envoyé."
        case .httpStatus(let code, _):
            "Le forum a renvoyé l’erreur \(code) : rien n’a été envoyé. Réessayez plus tard."
        case .invalidRequest, .invalidResponse, .transport, .unscripted:
            "La connexion au forum a échoué : rien n’a été envoyé. Réessayez."
        }
    }
}
