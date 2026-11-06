import Foundation
import HFRClient
import HFRModels
import HFRNetwork

/// The two flag writes the lists and the message menu send (LOT-125), in the current account's session. A seam over
/// `TopicFlagFlow`, whose session-check seam is internal, so the models are tested without HFR.
protocol TopicFlagWriting: Sendable {
    /// Removes `topic` from the favourites the way the list does (`TopicFlagFlow.removeFavoriteFromList`).
    func removeFavorite(_ topic: TopicID) async throws(TopicFlagError) -> TopicFlagResult
    /// Puts the topic in the favourites by following a message's `addflag.php` link (`TopicFlagFlow.addFavorite`).
    func addFavorite(link: URL) async throws(TopicFlagError) -> TopicFlagResult
}

/// LOT-051's flow in one account session.
struct LiveTopicFlagWriter: TopicFlagWriting {
    /// The current account's session (`AppEnvironment.session`, built only when an account is current).
    let session: HFRSession
    let flow = TopicFlagFlow()

    func removeFavorite(_ topic: TopicID) async throws(TopicFlagError) -> TopicFlagResult {
        try await flow.removeFavoriteFromList(topic, in: session)
    }

    func addFavorite(link: URL) async throws(TopicFlagError) -> TopicFlagResult {
        try await flow.addFavorite(link: link, in: session)
    }
}

/// How a flag write ended, as the user is told.
enum TopicFlagOutcome: Equatable, Sendable {
    /// HFR confirmed the write with its own sentence, shown as is.
    case done(String)
    /// The write was not done, or may have been: the row stays as it was and `reason` says why, in French.
    case failed(String)
}

// Port of HFRswift/Swift/Favorites.swift (ForumFavoritesTopicActionService.removeFavoriteFlag, FavoritesTopicActionError) and
// of HFRswift/Swift/MessagesView.swift (performFavoriteAction, `:1945-1961`) @ 2440d79. Differences: GAP-035; the writes go
// through LOT-051 (a session check first, success only on HFR's own sentence, a write that may have left is reported, never
// resent), and every failure says why in French instead of legacy's English-tinted texts or "Favori mis à jour" on any answer.
/// The flag actions of the current account (LOT-125): "Supprimer" on a list row and "Favoris" in the message menu (LOT-087).
struct TopicFlagActions: Sendable {
    let writer: any TopicFlagWriting

    /// Removes `topic` from the favourites (legacy `removeFavoriteFlag`, the same POST in both lists).
    func removeFavorite(_ topic: TopicID) async -> TopicFlagOutcome {
        do throws(TopicFlagError) {
            return .done(try await writer.removeFavorite(topic).message)
        } catch {
            return .failed(Self.reason(for: error))
        }
    }

    /// Adds the topic of a message's flag link to the favourites (legacy message menu "Favoris").
    func addFavorite(link: URL) async -> TopicFlagOutcome {
        do throws(TopicFlagError) {
            return .done(try await writer.addFavorite(link: link).message)
        } catch {
            return .failed(Self.reason(for: error))
        }
    }

    /// What the user is told for `error`: whether anything left, and what to do. An unconfirmed write is never resent.
    static func reason(for error: TopicFlagError) -> String {
        switch error {
        case .invalidLink, .invalidTopic:
            "Sujet invalide : rien n'a été envoyé."
        case .sessionNotConfirmed:
            "Session non confirmée : rien n'a été envoyé. Reconnectez-vous puis réessayez."
        case .missingToken:
            "Session incomplète : rien n'a été envoyé. Actualisez la liste puis réessayez."
        case .notLoggedIn:
            "HFR demande d'être connecté : reconnectez-vous puis réessayez."
        case .rejected(let message):
            message.map { "HFR a refusé : \($0)" } ?? "HFR a refusé l'action."
        case .unconfirmed:
            "HFR n'a pas confirmé l'action, qui a pu être faite. Actualisez pour vérifier avant de recommencer."
        case .network:
            "Réseau indisponible : rien n'a été envoyé."
        }
    }
}
