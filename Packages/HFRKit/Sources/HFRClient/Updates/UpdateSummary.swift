import Foundation
import HFRModels
import HFRNetwork

/// Why one source of a check gave no answer.
public enum UpdateFailure: Error, Sendable, Equatable {
    /// The page could not be fetched (offline, timeout, HTTP 4xx/5xx).
    case network(NetworkError)
    /// HFR answered, but the page is in maintenance, unreadable, or not served in place.
    case page(ListPageFailure)
    /// HFR refused the account's cookies (its stale-session page, `R70a` and `R70b`, #383).
    case sessionExpired(SessionExpiry)
}

/// What one source of a check found.
public enum UpdateOutcome<Value: Sendable & Equatable>: Sendable, Equatable {
    /// HFR's page answered the question.
    case value(Value)
    /// The page gave no information (logged out, or not the expected page): neither "none" nor proof of an expiry.
    case noInformation
    /// The source failed; the other one is still reported.
    case failed(UpdateFailure)
}

/// What a check found: the unread private messages and the flagged topics, each with its own outcome.
///
/// A source that did not answer is never a zero: `unreadPrivateMessages` is `.value(0)` only when HFR's page said 0, and
/// `flaggedTopics` is `.value([])` only for a list page with no row (`R123g`).
public struct UpdateSummary: Sendable, Equatable {
    /// The unread private messages count (`MPUnreadPoll`).
    public var unreadPrivateMessages: UpdateOutcome<Int>
    /// The topics of the account's flags page (flags and favourites, told apart by `TopicSummary.flag`),
    /// the most recent last post first (`FlaggedTopicsPoll`).
    public var flaggedTopics: UpdateOutcome<[TopicSummary]>

    /// Creates a summary.
    public init(unreadPrivateMessages: UpdateOutcome<Int>, flaggedTopics: UpdateOutcome<[TopicSummary]>) {
        self.unreadPrivateMessages = unreadPrivateMessages
        self.flaggedTopics = flaggedTopics
    }

    /// The flagged topics that may hold news since `date`: those whose last post is later, and those whose last post has no
    /// date (an unknown is not "older"). The flags page does not say what the member has read (the flag link's `page=` can
    /// be stale, the flag facts of `R123g`'s run, HFR-PROTOCOL §6c), so "news" is relative to a moment the caller keeps (LOT-091's
    /// ledger), not to the page.
    /// - Returns: nil when the flags did not answer, so a failure is never read as "no news".
    public func flaggedTopics(postedAfter date: Date) -> [TopicSummary]? {
        guard case .value(let topics) = flaggedTopics else { return nil }
        return topics.filter { topic in topic.lastPost?.date.map { $0 > date } ?? true }
    }
}
