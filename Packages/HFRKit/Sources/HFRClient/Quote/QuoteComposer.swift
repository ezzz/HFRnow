import HFRModels

/// A reply composer HFR prefilled with quotes, ready to be edited and posted through `QuoteFlow.reply`.
public struct QuoteComposer: Sendable {
    /// The reply form, fetched through the account's session; it can only be posted through that session.
    public let form: PostingForm
    /// HFR's `content_form` prefill, entity-decoded with line breaks as `\n` (LOT-036): the `[quotemsg=…]` blocks are the
    /// server's own, never rebuilt. The flow posts it with CRLF line breaks, as a browser does; HFR accepted `W14`'s bytes
    /// as served.
    public let prefill: String
    /// For a multi-quote, a message of the selected topic and the selection read before the composer's request:
    /// those are unselected once HFR confirms the reply. Nil for a single quote, which leaves the selection alone.
    let selection: (token: QuoteSelectionToken, numbers: [Int])?
    let session: any QuotingSession
}
