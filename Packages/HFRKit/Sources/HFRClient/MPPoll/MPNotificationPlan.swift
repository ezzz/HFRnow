import HFRModels
import HFRParsing

// Replaces the fixed text of HFRswift/Swift/MPBackgroundService.swift:98-101, 140-160 @ 87fe0d1c ("Vous avez un nouveau
// message privé", random identifier). Operator decisions of 2026-11-07 on #230: one notification per conversation, text
// from the MP list row, a burst collapsed into one summary.
/// The notifications the background MP check shows for the conversations with news (LOT-140), from MP list page 1.
///
/// Pure: the news come from the ledger (LOT-091), the rows from `PrivateMessageListParser`; no message content is shown.
public struct MPNotificationPlan: Sendable, Hashable {
    /// More conversations with news than this collapse into one summary notification.
    public static let burstLimit = 5
    /// Identifier of the summary notification, which opens the list.
    public static let summaryIdentifier = "mp-summary"

    /// What to show, in the page's order.
    public var notifications: [MPNotificationContent]

    /// True when there is nothing to show.
    public var isEmpty: Bool { notifications.isEmpty }

    /// The plan for the topic numbers in `newThreads`, read from the rows of `page`; a number the page does not list
    /// gives no notification.
    public static func make(newThreads: [Int], in page: PrivateMessageListPage) -> MPNotificationPlan {
        let wanted = Set(newThreads)
        let rows = page.threads.filter { thread in
            guard let number = thread.summary.topicID?.topic else { return false }
            return wanted.contains(number)
        }
        // A row listed twice (a page changing while it was served) still gives one notification.
        var seen = Set<Int>()
        let unique = rows.filter { seen.insert($0.summary.topicID?.topic ?? 0).inserted }
        guard unique.count <= burstLimit else {
            return MPNotificationPlan(notifications: [
                MPNotificationContent(
                    identifier: summaryIdentifier, threadIdentifier: summaryIdentifier, title: "Messages privés",
                    body: "\(unique.count) nouveaux messages privés", topic: nil
                )
            ])
        }
        return MPNotificationPlan(notifications: unique.compactMap(content(for:)))
    }

    /// Mirrors the list row: one-to-one, the interlocutor then the title; group, the title alone.
    private static func content(for thread: PrivateMessageThread) -> MPNotificationContent? {
        guard let number = thread.summary.topicID?.topic else { return nil }
        let identifier = "mp-\(number)"
        let title = thread.summary.displayTitle
        if thread.isGroup {
            return MPNotificationContent(identifier: identifier, threadIdentifier: identifier, title: title, body: "", topic: number)
        }
        let interlocutor = thread.interlocutors.first.map(HFRText.normalizedPseudo) ?? ""
        // A row whose interlocutor cell was empty still names the conversation.
        guard !interlocutor.isEmpty else {
            return MPNotificationContent(identifier: identifier, threadIdentifier: identifier, title: title, body: "", topic: number)
        }
        return MPNotificationContent(identifier: identifier, threadIdentifier: identifier, title: interlocutor, body: title, topic: number)
    }
}
