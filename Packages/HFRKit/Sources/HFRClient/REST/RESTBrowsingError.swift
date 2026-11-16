import HFRModels
import HFRNetwork
import HFRParsing

/// Why `RESTBrowsingClient` returned no list or topic (LOT-057).
public enum RESTBrowsingError: Error, Sendable, Equatable {
    /// The category or topic is not a forum one (`cat` 1 or more, topic 1 or more), or a posts-per-page below 1; nothing was
    /// sent.
    case invalidTarget
    /// The last request could not be built or sent, HFR answered an HTTP error, or the task was cancelled.
    case network(NetworkError)
    /// The HTML page read after a failed REST answer is not the list (maintenance, unreadable page).
    case page(ListPageFailure)
    /// A REST answer without HTML fallback (`topic(_:)`, a list page after the first) is not the JSON expected.
    case response(ParsingError)
    /// A REST answer without HTML fallback is HFR's error answer (`R57i`, `R57k`): the code is in the body.
    case refused(code: Int)
    /// HFR knows no such topic: `topic(_:)` got its placeholder (`R57j`: empty title, null date).
    case notFound
    /// HFR refused the account's cookies on the fallback page (its stale-session page, `R70b`), as `SessionRefreshFlow`
    /// reports it (#383). `RESTFlagBucketClient` only: `RESTBrowsingClient` sends no cookie.
    case sessionExpired(SessionExpiry)
}
