import HFRModels
import HFRNetwork

/// Why a private messages poll gave no answer.
public enum MPUnreadPollError: Error, Sendable, Equatable {
    /// The home page could not be fetched (offline, timeout, HTTP 4xx/5xx, cancellation).
    case network(NetworkError)
    /// HFR answered, but the page is in maintenance or unreadable (`ListPageFailure`).
    case page(ListPageFailure)
}
