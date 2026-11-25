import HFRClient
import HFRNetwork

/// User-facing texts of the poll sheet (French). Each says whether the vote was counted and what to do next; HFR's own
/// sentence is shown when it gave one. Never a token or a cookie.
enum PollMessages {
    /// Shown when HFR confirmed the vote: HFR's sentence, else ours.
    static func confirmed(_ result: PollVoteResult) -> String {
        result.message.isEmpty ? "Ton vote a bien été pris en compte." : result.message
    }

    /// What to tell the user about a vote that did not end with HFR's confirmation. The sheet
    /// reloads the topic when the vote may have been counted (`PollModel`).
    static func message(for error: PollVoteError) -> String {
        switch error {
        case .notVotable:
            "Ce sondage n’accepte plus de vote."
        case .unsupportedPoll:
            "Ce type de sondage n’est pas encore pris en charge : vote depuis le site. Rien n’a été envoyé."
        case .invalidChoice, .missingToken:
            "Choisis une réponse ou actualise le sujet, puis réessaie. Rien n’a été envoyé."
        case .sessionNotConfirmed(let health):
            session(health)
        case .loginChanged:
            session(.unconfirmed(.sessionChanged))
        case .notLoggedIn:
            "Le forum te considère comme déconnecté : le vote n’a pas été compté. Reconnecte-toi depuis le menu Comptes, puis vote."
        case .alreadyVoted:
            "Tu as déjà voté à ce sondage (ou un de tes pseudos liés)."
        case .rejected(let message):
            message ?? "Le forum a refusé le vote : rien n’a été compté. Actualise le sujet puis réessaie."
        case .unconfirmed:
            "Le forum n’a pas confirmé le vote : il a peut-être été compté. "
                + "Actualise le sujet pour voir le sondage ; ne vote pas à nouveau avant de l’avoir vu."
        case .network(let error):
            network(error)
        }
    }

    /// The session check before the vote did not say `valid`: expired, another login adopted, or HFR proved nothing.
    private static func session(_ health: SessionHealth) -> String {
        switch health {
        case .expired:
            "Ta session a expiré : rien n’a été envoyé. Reconnecte-toi depuis le menu Comptes, puis vote."
        case .unconfirmed(.sessionChanged):
            "Le compte connecté a changé : rien n’a été envoyé. Vote à nouveau."
        case .valid, .unconfirmed:
            "Impossible de vérifier ta session : rien n’a été envoyé. Réessaie dans quelques instants."
        }
    }

    private static func network(_ error: NetworkError) -> String {
        switch error {
        case .offline:
            "Pas de connexion à internet : rien n’a été envoyé. Réessaie une fois connecté."
        case .timedOut:
            "Le forum ne répond pas : rien n’a été envoyé. Réessaie dans quelques instants."
        case .cancelled:
            "Vote annulé : rien n’a été envoyé."
        case .httpStatus(let code, _):
            "Le forum a renvoyé l’erreur \(code) : rien n’a été envoyé. Réessaie plus tard."
        case .invalidRequest, .invalidResponse, .transport, .unscripted:
            "La connexion au forum a échoué : rien n’a été envoyé. Réessaie."
        }
    }
}
