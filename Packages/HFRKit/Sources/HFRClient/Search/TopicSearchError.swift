import Foundation
import HFRNetwork

/// Why a search inside a topic gave no answer (LOT-046).
public enum TopicSearchError: Error, Sendable, Equatable {
    /// No `hash_check` is recorded for the session yet; nothing was sent (HFR-PROTOCOL S3 requires it).
    case missingToken
    /// The request could not be built (no word nor author) or sent, HFR answered an HTTP error, or the task was cancelled
    /// before the request left.
    case network(NetworkError)
    /// HFR says the session is not logged in.
    case notLoggedIn(message: String?)
    /// HFR refused the search, for example an invalid token (`W17b`'s plain text); the message is HFR's.
    case rejected(message: String?)
    /// The redirect leaves the forum, or is not a page of the searched topic; it is returned to no one.
    case invalidLocation(URL)
    /// A redirect without a usable `Location`, or a page that is neither HFR's "no match" nor a refusal.
    case unrecognizedAnswer(message: String?)
}
