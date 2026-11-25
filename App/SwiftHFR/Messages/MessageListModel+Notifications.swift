import HFRModels
import HFRStorage

// LOT-140: what the MP notifications need from the list (GAP-011), apart from the model's main file.
extension MessageListModel {
    /// A tap on a conversation's notification (LOT-140, GAP-011): page 1 is loaded again, then the conversation is opened
    /// when that page lists it, on its segment unless Tous shows it. Otherwise the list stays shown (another account's
    /// conversation, or one no longer on page 1). Legacy opened the list and reloaded it (`MainWindow.swift:1656-1665`).
    func open(topic: Int) async {
        await showFirstPage()
        guard loader.error == nil,
              let thread = loader.value?.threads.first(where: { $0.summary.topicID?.topic == topic }) else { return }
        if !segment.contains(thread) { chooseSegment(thread.isGroup ? .group : .oneToOne, remember: false) }
        selected = thread
    }

    /// `thread`, marked unread here, to the ledger alone (#1006), with the reply count and last post its row shows: the member's
    /// own mark unread is not news. Page 1's rows only, as the ledger's set is page 1's; nothing without a thread number.
    func recordUnread(_ thread: PrivateMessageThread) async {
        guard let ledgerThread, let content = loader.value, content.page == 1, content != .signedOut,
              let topic = thread.summary.topicID?.topic else { return }
        let summary = thread.summary
        await ledgerThread(topic, UnreadThreadMark(topic: topic, repliesCount: summary.repliesCount, lastPost: summary.lastPost?.date))
    }

    /// Page 1's unread conversations as shown now (HFR's state, less what was read here, plus what was marked unread here),
    /// to the ledger (LOT-140). Called after the newest load applied, a read and a mark unread: a conversation read here
    /// leaves the ledger's set (its next reply is news), and the member's own mark unread is not news. No count: the list
    /// carries none, and the badge's may be stale (review r3). Nothing for other pages or the signed-out content.
    func recordReadState() async {
        guard let ledgerSeen, let content = loader.value, content.page == 1, content != .signedOut else { return }
        await ledgerSeen(MPNotificationLedger.seenSummary(of: content.threads.filter(isUnread)))
    }

    /// The row the list holds now for `thread`'s conversation, else `thread`: the reader keeps the value of the tap, which a
    /// later load may have made stale (a row since read must not take a second one off the badge, #762). Off the page, the
    /// thread's "opened here" mark is kept by `load`, so the fallback still reads as read.
    func listed(_ thread: PrivateMessageThread) -> PrivateMessageThread {
        loader.value?.threads.first { $0.id == thread.id } ?? thread
    }
}
