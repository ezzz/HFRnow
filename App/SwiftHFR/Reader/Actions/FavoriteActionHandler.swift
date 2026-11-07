import Foundation

// Port of HFRswift/Swift/MessagesView.swift (the `.favorite` entry, `:1718-1730`; performFavoriteAction, `:1945-1961`) @ 2440d79.
// Differences: GAP-064; the flag link goes through LOT-051's `addFavorite` (a session check first, success only on HFR's own
// sentence), where legacy showed "Favori mis à jour" for any answer and "Erreur réseau" for every failure.
/// "Favoris" in the message menu (LOT-087): puts the topic in the account's favourites from the message's flag link, through
/// the list actions of LOT-125. Shown only with a flag link and an account.
@MainActor
struct FavoriteActionHandler: MessageActionHandler {
    /// The current account's flag writes.
    let actions: TopicFlagActions
    /// Tells the user HFR's sentence, or why nothing is confirmed.
    let confirm: @MainActor (String) -> Void

    var kind: MessageMenuAction.Kind { .favorite }

    func isAvailable(for context: MessageMenuContext) -> Bool { context.canBeFavorite }

    func perform(with context: MessageMenuContext) async {
        guard let link = context.actions.favoriteURL else { return }
        switch await actions.addFavorite(link: link) {
        case .done(let message), .failed(let message): confirm(message)
        }
    }
}
