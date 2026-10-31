import HFRModels
import HFRNetwork
import HFRParsing

/// Why `RESTBrowsingClient` returned no list or topic (LOT-057).
public enum RESTBrowsingError: Error, Sendable, Equatable {
    /// The category or topic is not a forum one (`cat` 1 or more, topic 1 or more); nothing was sent.
    case invalidTarget
    /// The last request could not be built or sent, HFR answered an HTTP error, or the task was cancelled.
    case network(NetworkError)
    /// The HTML page read after a failed REST answer is not the list (maintenance, unreadable page).
    case page(ListPageFailure)
    /// The REST answer of `topic(_:)`, which has no HTML fallback, is not the JSON expected.
    case response(ParsingError)
}
