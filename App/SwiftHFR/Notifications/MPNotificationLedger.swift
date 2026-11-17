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
        NotificationSummary(unreadThreads: Set(page.threads.filter(\.isUnread).compactMap { $0.summary.topicID?.topic }))
    }
}
