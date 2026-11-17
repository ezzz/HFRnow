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

    /// Page 1's unread conversations as shown now, and the badge's count, to the ledger (LOT-140): a conversation read here
    /// leaves the ledger's unread set, so its next reply is news again. Other pages say nothing about page 1.
    func recordFirstPageReadState() {
        guard let ledgerSeen, let content = loader.value, content.page == 1 else { return }
        var summary = NotificationSummary(
            unreadThreads: Set(content.threads.filter(isUnread).compactMap { $0.summary.topicID?.topic })
        )
        summary.unreadPrivateMessages = privateMessageCount?.latest
        Task { await ledgerSeen(summary) }
    }
}
