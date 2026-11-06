import HFRModels

// Port of HFRswift/Swift/Favorites.swift (markTopicAsRead, removeFavoriteFlag, `:841-886`) and HFRswift/Swift/MainWindow.swift
// (markTopicAsRead, removeFlag, `:536-570`) @ 2440d79. Differences: GAP-029, GAP-034, GAP-035; "Lu" stays local as in legacy and
// lasts until the next load of the list; "Supprimer" goes through LOT-051 and a row leaves the list only on HFR's confirmation.
/// The row actions of a topic list (LOT-125): the leading "Lu" and trailing "Supprimer" swipes, also in the row's menu and
/// as VoiceOver actions. Legacy offers both on every favourites row and on a forum row that has a flag.
extension TopicListModel {
    /// The row has a flag the user can act on: every row of flags and favourites, a flagged row of a forum, until its flag
    /// is removed.
    func hasFlag(_ topic: TopicSummary) -> Bool {
        (source.isFavoritesList || topic.flag != nil) && !removedFlags.contains(topic.id)
    }

    /// The user marked the row "Lu" since the last load.
    func isMarkedRead(_ topic: TopicSummary) -> Bool { markedRead.contains(topic.id) }

    /// The row shows as read: HFR said so, or the user marked it "Lu" since the last load.
    func isRead(_ topic: TopicSummary) -> Bool { topic.readState != .unread || isMarkedRead(topic) }

    /// "Lu" is offered (legacy: on a flagged row, whatever its read state).
    func canMarkRead(_ topic: TopicSummary) -> Bool { hasFlag(topic) }

    /// "Lu": the row shows as read until the next load. Nothing is sent to HFR (legacy `markTopicAsRead`, GAP-034).
    func markRead(_ topic: TopicSummary) {
        guard canMarkRead(topic) else { return }
        markedRead.insert(topic.id)
    }

    /// "Supprimer" is offered: logged in, a flag to remove and a topic number to name.
    func canRemoveFlag(_ topic: TopicSummary) -> Bool {
        flagActions != nil && topic.topicID != nil && hasFlag(topic)
    }

    /// The removal of the row's flag is in flight ("Suppression…", disabled).
    func isRemovingFlag(_ topic: TopicSummary) -> Bool { removingFlags.contains(topic.id) }

    /// "Supprimer": removes the row's flag (legacy `removeFavoriteFlag`, the favourites list POST). On HFR's confirmation the
    /// row leaves the flags and favourites lists, and a forum row loses its flag; otherwise the row stays and
    /// `actionFailure` says why. A removal in flight is not sent a second time, and an unconfirmed one is never resent.
    func removeFlag(_ topic: TopicSummary) async {
        guard let flagActions, let topicID = topic.topicID, hasFlag(topic), !removingFlags.contains(topic.id) else { return }
        removingFlags.insert(topic.id)
        defer { removingFlags.remove(topic.id) }
        switch await flagActions.removeFavorite(topicID) {
        case .done:
            removedFlags.insert(topic.id)
        case .failed(let reason):
            actionFailure = reason
        }
    }

    /// Hides the failure once read.
    func clearActionFailure() {
        actionFailure = nil
    }
}
