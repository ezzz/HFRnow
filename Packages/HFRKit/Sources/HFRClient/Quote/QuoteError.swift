/// Why a quote composer could not be opened. No case carries a token, a cookie or the quoted text.
public enum QuoteError: Error, Sendable, Equatable {
    /// The message has no quote link (LOT-031 found none on the forum): nothing was requested.
    case noQuoteLink
    /// No message of the topic is selected for a multi-quote: nothing was requested.
    case emptySelection
    /// HFR served a composer without quote: not a reply form, or an empty `content_form`.
    case noQuote
    /// The composer HFR served belongs to another topic than the multi-quote selection: it must not be posted.
    case otherTopic
    /// The composer could not be loaded: LOT-048's error (`notLoggedIn`, `formUnavailable`, `network`…).
    case form(PostingError)
}
