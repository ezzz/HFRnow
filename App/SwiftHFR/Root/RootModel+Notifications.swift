// Port of HFRswift/Swift/MainWindow.swift (RootTabView.syncAppIconBadge, :1564-1567; handlePendingMessagesNotificationNavigationIfNeeded,
// :1656-1665) @ 87fe0d1c. Differences: a tap can open the conversation (GAP-011), and no icon badge before a page gave a count,
// so the one the background check set stays (GAP-192).
extension RootModel {
    /// The app icon badge the running app shows: the Messages badge's count, 0 when the badge setting is off; nil until a page
    /// gave a count.
    var appIconBadge: Int? {
        guard privateMessageBadgeEnabled else { return 0 }
        return privateMessageCount.latest.map { max($0, 0) }
    }

    /// Opens what an MP notification leads to (LOT-140): the Messages tab, then the conversation, or the list reloaded as
    /// legacy did.
    func open(_ destination: MPNotificationDestination) async {
        selectedDestination = .tab(.messages)
        switch destination {
        case .thread(let topic): await messages.open(topic: topic)
        case .list: await messages.refresh()
        }
    }
}
