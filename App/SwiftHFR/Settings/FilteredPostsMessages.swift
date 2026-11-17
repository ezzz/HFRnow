import Foundation

/// The words of the info bubble on « Filtrer les posts » in Réglages (#1072). The rules follow `FilteredPostsCriteria.keeps`
/// (a port of legacy `ParseMessagesOperation.m:176-347`): a message is kept when it was quoted at least the minimum number of
/// times (HFR's « Message cité N fois »), or is the account's own, or quotes or mentions its pseudo, or is by a whitelisted
/// author while « Inclure les pseudos whitelistés » is on. The filter starts from a topic's « … » menu in the reader, and from
/// the favourites list's menu.
enum FilteredPostsMessages {
    /// The accessibility label of the (i) button that opens `explanation` in a bubble.
    static let infoLabel = "À propos du filtre des posts"

    /// What the filter keeps, then what « Minimum de citations » is and how it acts.
    static let explanation = [
        "Depuis un sujet (menu … › Filtrer les posts), n’affiche que les messages cités au moins N fois, les vôtres, "
            + "ceux qui vous citent ou vous mentionnent, et ceux de votre liste blanche si l’option est activée.",
        "« Minimum de citations » est ce N : plus il est grand, moins il reste de messages."
    ]
}
