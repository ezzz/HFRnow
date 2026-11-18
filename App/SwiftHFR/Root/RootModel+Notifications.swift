// Port of HFRswift/Swift/MainWindow.swift (RootTabView.syncAppIconBadge, :1564-1567; handlePendingMessagesNotificationNavigationIfNeeded,
// :1656-1665) @ 87fe0d1c. Differences: a tap can open the conversation (GAP-011), and no icon badge before a page gave a count,
// so the one the background check set stays (GAP-192), except in a root logged out or rebuilt on a new session, which clears it
// until its own count (LOT-156, as legacy's switch and logout reset `nb_mp`: `MultisManager.m:107-123`, `:155-166`,
// `HFRplusAppDelegate.m:704-706`, `:788-793`).
extension RootModel {
    /// The app icon badge the running app shows: the Messages badge's count, 0 when the badge setting is off; until a page gave
    /// a count, nil (left alone), or 0 when the icon may show another account's count (`clearsIconBadgeBeforeCount`, LOT-156).
    var appIconBadge: Int? {
        guard privateMessageBadgeEnabled else { return 0 }
        guard let latest = privateMessageCount.latest else { return clearsIconBadgeBeforeCount ? 0 : nil }
        return max(latest, 0)
    }

    /// Opens what an MP notification leads to (LOT-140): the Messages tab, then the conversation, or page 1 of the list reloaded
    /// (legacy reloaded the list).
    func open(_ destination: MPNotificationDestination) async {
        selectedDestination = .tab(.messages)
        switch destination {
        case .thread(let topic): await messages.open(topic: topic)
        case .list: await messages.showFirstPage()
        }
    }
}
