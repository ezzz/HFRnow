import HFRStorage

// LOT-140: what the MP notifications need from the list (GAP-011), apart from the model's main file.
extension MessageListModel {
    /// A tap on a conversation's notification (LOT-140, GAP-011): page 1 is loaded again, then the conversation is opened
    /// when that page lists it, on its segment in the split display. Otherwise the list stays shown (another account's
    /// conversation, or one no longer on page 1). Legacy opened the list and reloaded it (`MainWindow.swift:1656-1665`).
    func open(topic: Int) async {
        await showFirstPage()
        guard loader.error == nil,
              let thread = loader.value?.threads.first(where: { $0.summary.topicID?.topic == topic }) else { return }
        if display == .split, !segment.contains(thread) { segment = thread.isGroup ? .group : .oneToOne }
        selected = thread
    }

    /// Page 1's unread conversations as shown now (HFR's state, less what was read here, plus what was marked unread here),
    /// to the ledger (LOT-140). Called after the newest load applied, a read and a mark unread: a conversation read here
    /// leaves the ledger's set (its next reply is news), and the member's own mark unread is not news. No count: the list
    /// carries none, and the badge's may be stale (review r3). Nothing for other pages or the signed-out content.
    func recordReadState() async {
        guard let ledgerSeen, let content = loader.value, content.page == 1, content != .signedOut else { return }
        await ledgerSeen(NotificationSummary(
            unreadThreads: Set(content.threads.filter(isUnread).compactMap { $0.summary.topicID?.topic })
        ))
    }
}
