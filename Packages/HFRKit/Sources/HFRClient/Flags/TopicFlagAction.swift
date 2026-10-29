/// A topic flag write, each with the sentence HFR confirms it with.
public enum TopicFlagAction: String, Sendable, Hashable, CaseIterable {
    /// Puts the topic in the favourites: GET of a message's `addflag.php` link (`P03a`; again, `P03b`).
    case addFavorite
    /// Removes the topic's flag: GET of a topic page's `delflag.php` link (`P03d`, favourite removed with its read flag, `P03f`).
    case removeFlag
    /// Removes a favourite from the favourites list: POST of the list's `message_forum_delflags` action to `manageaction.php`.
    case removeFavoriteFromList

    /// HFR's confirmations of this write, each compared with the whole `.hop` sentence.
    ///
    /// The list removal has two: the sentence depends on the body, and the captures do not show whether `owntopic` or
    /// the end marker selects it ("Drapeaux effacés" for legacy's body, `P03j`; "Favoris supprimés" for the browser's,
    /// `P03h`, `P03l`). Both removed the topic, and neither confirms another write.
    var confirmations: Set<String> {
        switch self {
        case .addFavorite: ["Favori positionné avec succès"]
        case .removeFlag: ["Drapeau effacé avec succès"]
        case .removeFavoriteFromList: ["Drapeaux effacés avec succès", "Favoris supprimés avec succès"]
        }
    }

    /// Path of the link a GET write follows (`R21`, `P03a`, `P03d`); nil for the POST.
    var linkPath: String? {
        switch self {
        case .addFavorite: "/user/addflag.php"
        case .removeFlag: "/user/delflag.php"
        case .removeFavoriteFromList: nil
        }
    }
}
