import Foundation
import OSLog
import HFRClient
import HFRModels
import HFRNetwork

/// The flag writes the lists, the message menu (LOT-125) and a conversation's menu (LOT-127) send, in the current account's
/// session. A seam over `TopicFlagFlow`, whose session-check seam is internal, so the models are tested without HFR.
protocol TopicFlagWriting: Sendable {
    /// Removes `topic` from the favourites the way the list does (`TopicFlagFlow.removeFavoriteFromList`).
    func removeFavorite(_ topic: TopicID) async throws(TopicFlagError) -> TopicFlagResult
    /// Puts the topic in the favourites by following a message's `addflag.php` link (`TopicFlagFlow.addFavorite`).
    func addFavorite(link: URL) async throws(TopicFlagError) -> TopicFlagResult
    /// Puts `topic` in the favourites from a list: its `page` is read and its last message's `addflag.php` link followed
    /// (`TopicFlagFlow.addFavorite(_:fromLastMessageOfPage:in:)`, #869).
    func addFavorite(_ topic: TopicID, fromLastMessageOfPage page: Int) async throws(TopicFlagError) -> TopicFlagResult
    /// Marks a private conversation unread by following its page's `nonlu.php` link (`TopicFlagFlow.markUnread`).
    func markUnread(link: URL) async throws(TopicFlagError) -> TopicFlagResult
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

    func addFavorite(_ topic: TopicID, fromLastMessageOfPage page: Int) async throws(TopicFlagError) -> TopicFlagResult {
        try await flow.addFavorite(topic, fromLastMessageOfPage: page, in: session)
    }

    func markUnread(link: URL) async throws(TopicFlagError) -> TopicFlagResult {
        try await flow.markUnread(link: link, in: session)
    }
}

/// How a flag write ended, as the user is told.
enum TopicFlagOutcome: Equatable, Sendable {
    /// HFR confirmed the write with its own sentence, shown as is.
    case done(String)
    /// The write was not done, or may have been: the row stays as it was and `reason` says why, in French.
    case failed(String)
    /// Nothing was sent and sending again may work (the session check proved nothing, the network failed before the
    /// write): `reason` says why, and the list offers « Réessayer » (#1056).
    case retryable(String)
}

// Port of HFRswift/Swift/Favorites.swift (ForumFavoritesTopicActionService.removeFavoriteFlag, FavoritesTopicActionError) and
// of HFRswift/Swift/MessagesView.swift (performFavoriteAction, `:1945-1961`) @ 2440d79. Differences: GAP-035; the writes go
// through LOT-051 (a session check first, success only on HFR's own sentence, a write that may have left is reported, never
// resent), and every failure says why in French instead of legacy's English-tinted texts or "Favori mis à jour" on any answer.
/// The flag actions of the current account (LOT-125): "Supprimer" on a list row, "Favoris" in the message menu (LOT-087) and
/// "Marquer comme non lu" on a private conversation (LOT-127).
struct TopicFlagActions: Sendable {
    let writer: any TopicFlagWriting

    /// Removes `topic` from the favourites (legacy `removeFavoriteFlag`, the same POST in both lists).
    func removeFavorite(_ topic: TopicID) async -> TopicFlagOutcome {
        do throws(TopicFlagError) {
            return .done(try await writer.removeFavorite(topic).message)
        } catch {
            return Self.outcome(for: error)
        }
    }

    /// Adds the topic of a message's flag link to the favourites (legacy message menu "Favoris").
    func addFavorite(link: URL) async -> TopicFlagOutcome {
        do throws(TopicFlagError) {
            return .done(try await writer.addFavorite(link: link).message)
        } catch {
            return Self.outcome(for: error)
        }
    }

    /// Adds `topic` to the favourites from a list row (#869): its `page` is read first, which moves the read flag to its end.
    func addFavorite(_ topic: TopicID, fromLastMessageOfPage page: Int) async -> TopicFlagOutcome {
        do throws(TopicFlagError) {
            return .done(try await writer.addFavorite(topic, fromLastMessageOfPage: page).message)
        } catch {
            return Self.outcome(for: error)
        }
    }

    /// Marks unread the private conversation whose page gave `link` (legacy `markUnread`). A failure is never shown as done.
    func markUnread(link: URL) async -> TopicFlagOutcome {
        do throws(TopicFlagError) {
            return .done(try await writer.markUnread(link: link).message)
        } catch {
            return Self.outcome(for: error)
        }
    }

    private static let log = Logger(subsystem: "SwiftHFR", category: "session")

    /// The outcome of a failed write: retryable only when nothing left and the cause may pass (#1056). A write that may
    /// have been done (`unconfirmed`) is never offered again.
    static func outcome(for error: TopicFlagError) -> TopicFlagOutcome {
        if case .sessionNotConfirmed(let health) = error {
            // Case and reason only, never a cookie or a token: tells which check failed on a device (#1056).
            log.notice("flag write refused by the session check: \(String(describing: health), privacy: .public)")
        }
        return isRetryable(error) ? .retryable(reason(for: error)) : .failed(reason(for: error))
    }

    /// Whether sending again may succeed without the user doing anything else first (logging in, refreshing the list).
    static func isRetryable(_ error: TopicFlagError) -> Bool {
        switch error {
        case .sessionNotConfirmed(.unconfirmed), .sessionChanged, .network: true
        case .sessionNotConfirmed, .invalidLink, .invalidTopic, .missingToken, .favoriteLinkMissing, .notLoggedIn, .rejected,
             .unconfirmed: false
        }
    }

    /// What the user is told for `error`: whether anything left, and what to do. An unconfirmed write is never resent.
    static func reason(for error: TopicFlagError) -> String {
        switch error {
        case .invalidLink, .invalidTopic:
            "Sujet invalide : rien n'a été envoyé."
        case .sessionNotConfirmed(let health):
            session(health)
        case .sessionChanged:
            // A login landed between the check and the write (#1200 P2): the same words as a check that saw it.
            session(.unconfirmed(.sessionChanged))
        case .favoriteLinkMissing:
            "La dernière page du sujet ne propose pas l'ajout aux favoris : rien n'a été envoyé. Actualise la liste puis réessaie."
        case .missingToken:
            "Session incomplète : rien n'a été envoyé. Actualise la liste puis réessaie."
        case .notLoggedIn:
            "HFR demande d'être connecté : reconnecte-toi puis réessaie."
        case .rejected(let message):
            message.map { "HFR a refusé : \($0)" } ?? "HFR a refusé l'action."
        case .unconfirmed:
            "HFR n'a pas confirmé l'action, qui a pu être faite. Actualise pour vérifier avant de recommencer."
        case .network:
            "Réseau indisponible : rien n'a été envoyé."
        }
    }

    /// The session check said no (LOT-044): « Reconnectez-vous » only when HFR proved the session logged out; otherwise
    /// it could not tell, and the reason names which check failed, so a report from a device says it (#1056).
    static func session(_ health: SessionHealth) -> String {
        switch health {
        case .expired(.noIdentityCookie):
            "Session expirée : rien n'a été envoyé. Reconnecte-toi puis réessaie."
        case .expired(.credentialsRefused):
            "HFR refuse les identifiants de ce compte : rien n'a été envoyé. Reconnecte-toi puis réessaie."
        case .unconfirmed(.sessionChanged):
            "Le compte connecté a changé pendant la vérification : rien n'a été envoyé. Réessaie."
        case .unconfirmed(.unrecognizedPage):
            "Session non vérifiée (page de profil inattendue) : rien n'a été envoyé. Réessaie dans quelques instants."
        case .unconfirmed(.identityNotConfirmed):
            "Session non vérifiée (identité non confirmée par HFR) : rien n'a été envoyé. Réessaie dans quelques instants."
        case .valid:
            "Session non vérifiée : rien n'a été envoyé. Réessaie dans quelques instants."
        }
    }
}
