import HFRModels

// Port of HFRswift/Swift/Favorites.swift (trailing swipe « Supprimer », `:1198-1211`; super-favourite menu entry, `:1150-1158`) and
// HFRswift/Swift/MainWindow.swift (trailing swipe « Supprimer », `:761-770`) @ 87fe0d1c. Differences (#869, operator decisions of
// 2026-11-13 and 2026-11-28, M4): the trailing swipe names the favourite by its state (« Retirer des favoris » on a favourite,
// legacy « Supprimer » on another flag, « Ajouter aux favoris » on a row that is none) and adds « Ajouter aux / Retirer des super
// favoris » in every list, where legacy had the super favourite only in the Favoris row menu and no add from a list. The add
// reads the row's last page and follows its last message's `addflag.php` link (`TopicFlagFlow`, option A): the topic's read flag
// moves to the end of that page, as the operator accepted.
/// The flag swipes of a topic row (#869): the favourite action named by the row's state and the super-favourite toggle.
extension TopicListModel {
    /// The last flag change HFR confirmed from this list since the last load (a removal is of any flag), nil when there was
    /// none; the later of an addition and a removal wins.
    func confirmedFlagChange(_ topic: TopicSummary) -> ConfirmedFlagChange? {
        switch (addedFavorites[topic.id], removedFlags[topic.id]) {
        case (nil, nil): nil
        case (.some, nil): .favoriteAdded
        case (nil, .some): .flagRemoved
        case let (added?, removed?): added > removed ? .favoriteAdded : .flagRemoved
        }
    }

    /// The row is in the account's favourites: added from this list, HFR's `favoris.gif` (`TopicFlag.yellow`), or a list that
    /// only holds favourites (Favoris, the Favoris filter of a category), until HFR confirmed its removal.
    func isFavorite(_ topic: TopicSummary) -> Bool {
        if let change = confirmedFlagChange(topic) { return change == .favoriteAdded }
        return topic.flag == .yellow || source == .favorites || (source.isForumList && loadedFilter == .favorites)
    }

    /// The name of the flag removal on this row: « Retirer des favoris » on a favourite, legacy « Supprimer » on another flag
    /// (the same `manageaction.php` POST, `TopicFlagFlow.removeFavoriteFromList`).
    func removeFlagTitle(_ topic: TopicSummary) -> String {
        isFavorite(topic) ? "Retirer des favoris" : "Supprimer"
    }

    /// « Ajouter aux favoris » is offered: logged in, a forum topic that is not a favourite. It is the row's first trailing
    /// action; a followed or read row keeps legacy « Supprimer » after the super favourite.
    func canAddFavorite(_ topic: TopicSummary) -> Bool {
        guard flagActions != nil, let id = topic.topicID, case .forum = id.category else { return false }
        return !isFavorite(topic)
    }

    /// The addition of the row's favourite is in flight (« Ajout… », disabled).
    func isAddingFavorite(_ topic: TopicSummary) -> Bool { addingFavorites.contains(topic.id) }

    /// « Ajouter aux favoris » (#869, option A): the session is checked, the row's last page read and its last message's
    /// `addflag.php` link followed (`TopicFlagFlow.addFavorite(_:fromLastMessageOfPage:in:)`). On HFR's confirmation the row
    /// is a favourite until the next load; otherwise it stays as it was and the alert says why. One write per swipe: an
    /// addition in flight is not sent again, and an unconfirmed one is never resent.
    func addFavorite(_ topic: TopicSummary) async {
        guard let flagActions, let id = topic.topicID, canAddFavorite(topic), !addingFavorites.contains(topic.id) else { return }
        addingFavorites.insert(topic.id)
        defer { addingFavorites.remove(topic.id) }
        switch await flagActions.addFavorite(id, fromLastMessageOfPage: topic.pageCount) {
        case .done:
            rowActionSerial += 1
            addedFavorites[topic.id] = rowActionSerial
        case .failed(let reason):
            fail(.favoriteAddition, reason)
        case .retryable(let reason):
            fail(.favoriteAddition, reason)
            retryableAddition = topic
        }
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

    /// The title of the row-action alert: what failed (HIG › Alerts, #1175).
    var actionFailureTitle: String {
        switch actionFailureKind {
        case .flagRemoval: AlertTitles.flagRemoveFailed
        case .favoriteAddition: AlertTitles.favoriteAddFailed
        case .superFavoriteSave: AlertTitles.superFavoriteSaveFailed
        }
    }

    /// Adds or removes the row's super-favourite (`SuperFavoritesStore`, local, nothing sent to HFR; the store's add and remove are
    /// idempotent). A refused write leaves the row as it was; a forum list says why in its alert (the favourites lists show
    /// `storeProblem` above the rows already).
    func toggleSuperFavorite(_ topic: TopicSummary) async {
        guard let superFavoriteOptions, canToggleSuperFavorite(topic) else { return }
        if await !superFavoriteOptions.toggleSuperFavorite(topic), favorites == nil {
            fail(.superFavoriteSave, FavoritesOptionsModel.superWriteFailure)
        }
    }
}

/// A flag change HFR confirmed on a row of the list.
enum ConfirmedFlagChange: Equatable {
    /// « Ajouter aux favoris » (#869).
    case favoriteAdded
    /// « Supprimer » / « Retirer des favoris ».
    case flagRemoved
}

/// Which row action an alert of the topic list is about.
enum RowActionFailure: Equatable {
    /// « Supprimer » / « Retirer des favoris ».
    case flagRemoval
    /// « Ajouter aux favoris » (#869).
    case favoriteAddition
    /// « Ajouter aux / Retirer des super favoris ».
    case superFavoriteSave
}
