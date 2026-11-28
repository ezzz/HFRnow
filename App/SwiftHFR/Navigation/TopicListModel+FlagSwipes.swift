import HFRModels

// Port of HFRswift/Swift/Favorites.swift (trailing swipe « Supprimer », `:1198-1211`; super-favourite menu entry, `:1150-1158`) and
// HFRswift/Swift/MainWindow.swift (trailing swipe « Supprimer », `:761-770`) @ 87fe0d1c. Differences (#869, operator decision of
// 2026-11-13, M4): the trailing swipe names the favourite by its state (« Retirer des favoris » on a `favoris.gif` row, legacy
// « Supprimer » on another flag) and adds « Ajouter aux / Retirer des super favoris » in every list, where legacy had the super
// favourite only in the Favoris row menu. « Ajouter aux favoris » waits on a capture or a decision: a list row carries no
// `addflag.php` link (#869).
/// The flag swipes of a topic row (#869): the favourite action named by the row's state and the super-favourite toggle.
extension TopicListModel {
    /// The row is in the account's favourites: HFR's `favoris.gif` (`TopicFlag.yellow`), or a list that only holds favourites
    /// (Favoris, the Favoris filter of a category), until HFR confirmed its removal.
    func isFavorite(_ topic: TopicSummary) -> Bool {
        guard removedFlags[topic.id] == nil else { return false }
        return topic.flag == .yellow || source == .favorites || (source.isForumList && loadedFilter == .favorites)
    }

    /// The name of the flag removal on this row: « Retirer des favoris » on a favourite, legacy « Supprimer » on another flag
    /// (the same `manageaction.php` POST, `TopicFlagFlow.removeFavoriteFromList`).
    func removeFlagTitle(_ topic: TopicSummary) -> String {
        isFavorite(topic) ? "Retirer des favoris" : "Supprimer"
    }

    /// The super-favourite toggle is offered: an account whose super-favourites can be written, and a topic number.
    func canToggleSuperFavorite(_ topic: TopicSummary) -> Bool {
        superFavoriteOptions?.canMarkSuperFavorites == true && topic.topicID != nil
    }

    /// The row is a super-favourite of the current account (the swipe and menu label; the row's tint stays `isSuperFavorite`).
    func isMarkedSuperFavorite(_ topic: TopicSummary) -> Bool {
        guard let superFavoriteOptions else { return false }
        return FavoritesPresentation.isSuper(topic, in: superFavoriteOptions.superFavorites)
    }

    /// The super-favourite label that follows the row's state.
    func superFavoriteTitle(_ topic: TopicSummary) -> String {
        isMarkedSuperFavorite(topic) ? "Retirer des super favoris" : "Ajouter aux super favoris"
    }

    /// Adds or removes the row's super-favourite (`SuperFavoritesStore`, local, nothing sent to HFR; the store's add and remove are
    /// idempotent). A refused write leaves the row as it was; a forum list says why in its alert (the favourites lists show
    /// `storeProblem` above the rows already).
    func toggleSuperFavorite(_ topic: TopicSummary) async {
        guard let superFavoriteOptions, canToggleSuperFavorite(topic) else { return }
        if await !superFavoriteOptions.toggleSuperFavorite(topic), favorites == nil {
            actionFailure = FavoritesOptionsModel.superWriteFailure
        }
    }
}
