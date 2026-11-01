import HFRNetwork
import HFRParsing

/// Why a smiley search or wiki lookup gave no answer (LOT-053).
public enum SmileyLookupError: Error, Sendable, Equatable {
    /// The search text has fewer than `HFREndpoint.smileySearchMinimumLength` characters once trimmed; nothing was sent.
    case queryTooShort
    /// The smiley code is blank; nothing was sent.
    case invalidCode
    /// The page could not be fetched (offline, timeout, HTTP error, cancellation).
    case network(NetworkError)
    /// HFR answered, but not with a search answer or the wiki entry of that smiley.
    case page(ParsingError)
}
