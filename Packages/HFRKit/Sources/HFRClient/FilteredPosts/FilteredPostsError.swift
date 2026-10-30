import HFRNetwork
import HFRParsing

/// Why a filtering run stopped without a batch. The pages read before are not returned, as in legacy
/// (`FilterPostsQuotes.m:268-274`): the caller starts again from the same page.
public enum FilteredPostsError: Error, Sendable, Equatable {
    /// Only forum topics can be filtered (a private conversation is not readable without the session), from page 1.
    case invalidTopic
    /// A page could not be fetched, HFR answered an HTTP error, or the run was cancelled (`.cancelled`).
    case network(NetworkError)
    /// HFR served a page that is not a page of this topic (another topic, no message, no canonical URL).
    case unexpectedPage
    /// A page of the topic could not be read.
    case page(ParsingError)
}
