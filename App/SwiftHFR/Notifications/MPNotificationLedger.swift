import Foundation
import HFRModels
import HFRStorage

/// The device's notification ledger (LOT-091), one instance for the app: the background check (LOT-140), the screens that
/// record what they showed, and later the App Intent (LOT-141) share its actor, so their steps never interleave.
enum MPNotificationLedger {
    static let live = NotificationLedgerStore(
        persistence: FileSmallStorePersistence(
            fileURL: URL.applicationSupportDirectory.appending(path: "Notifications/ledger.json")
        )
    )

    /// Records what the app showed for `account` (LOT-091, legacy `HFRplusAppDelegate.m:706`): the next background check
    /// does not notify it. A failed write is not shown: the cost is one notification the member may already have seen.
    static func recordSeen(_ summary: NotificationSummary, account: String, store: NotificationLedgerStore = live) async {
        _ = try? await store.record(summary, account: account)
    }

    /// The unread conversations of an MP list page 1 the app showed.
    static func seenSummary(of page: PrivateMessageListPage) -> NotificationSummary {
        seenSummary(of: page.threads.filter(\.isUnread))
    }

    /// The conversations in `unread` with their reply count and last post (#571): a reply in a conversation that was
    /// already unread moves only those (HFR-PROTOCOL §6c LOT-140), so the ledger keeps them and the background check
    /// notifies it; a reply the member saw in the list is recorded here and not notified.
    static func seenSummary(of unread: [PrivateMessageThread]) -> NotificationSummary {
        let rows = unread.compactMap { thread in thread.summary.topicID.map { ($0.topic, thread.summary) } }
        return NotificationSummary(
            unreadThreads: Set(rows.map(\.0)),
            unreadThreadMarks: rows.map { UnreadThreadMark(topic: $0.0, repliesCount: $0.1.repliesCount, lastPost: $0.1.lastPost?.date) }
        )
    }
}
