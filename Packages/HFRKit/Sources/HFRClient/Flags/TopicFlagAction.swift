/// A topic flag write, each with the sentence HFR confirms it with.
public enum TopicFlagAction: String, Sendable, Hashable, CaseIterable {
    /// Puts the topic in the favourites: GET of a message's `addflag.php` link (`P03a`; again, `P03b`).
    case addFavorite
    /// Removes the topic's flag: GET of a topic page's `delflag.php` link (`P03d`, favourite removed with its read flag, `P03f`).
    case removeFlag
    /// Removes a favourite from the favourites list: POST of the list's `message_forum_delflags` action to `manageaction.php`.
    case removeFavoriteFromList

    /// HFR's confirmation for this write, compared with the whole `.hop` sentence; nil while no answer is captured.
    ///
    /// A `manageaction.php` answer was never captured (spec "Pending capture"): until it is, that write is reported
    /// `unconfirmed(.confirmationNotCaptured)` even when HFR says "avec succès", never as a success.
    var confirmation: String? {
        switch self {
        case .addFavorite: "Favori positionné avec succès"
        case .removeFlag: "Drapeau effacé avec succès"
        case .removeFavoriteFromList: nil
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
