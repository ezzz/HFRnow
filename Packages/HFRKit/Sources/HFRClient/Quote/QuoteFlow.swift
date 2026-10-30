import Foundation
import HFRModels
import HFRNetwork

/// Quote composers (LOT-049, audit D4): HFR prefills the reply form with the quotes, the app never builds them.
///
/// A single quote loads the message's LOT-031 quote link; a multi-quote loads the topic's answer link while the session
/// holds the topic's `quotes…` cookie, and HFR prefills one block per selected message (`R42`, `R47c`). Both go through
/// LOT-048's `PostingFlow.loadForm` in the selected account's session (`ReplyService.swift:767-841` used the main one).
public struct QuoteFlow: Sendable {
    private let posting = PostingFlow()

    /// Creates the flow.
    public init() {}

    /// The quote composer of one message: its quote link (`MessageActions.quoteURL`) fetched through `session`.
    ///
    /// The multi-quote selection is left as it is, whatever the reply's outcome.
    /// - Throws: `noQuoteLink` before any request, `form` when the page is not a form LOT-048 can post, `noQuote` when
    ///   the form is not a reply composer with a prefill.
    public func quote(_ message: MessageActions, in session: HFRSession) async throws(QuoteError) -> QuoteComposer {
        try await quote(message, through: session)
    }

    /// The topic's reply composer prefilled with the multi-quote selection of `token`'s topic.
    ///
    /// `answerFormURL` is the topic page's answer link (`TopicPage.answerFormURL`); the session sends the topic's
    /// `quotes…` cookie with it, as a browser does. Any message of the topic gives its `token` (`quoteSelection`).
    /// - Throws: `emptySelection` before any request, `form`, `noQuote`, and `otherTopic` when the form HFR served names
    ///   another topic.
    public func multiQuote(
        _ token: QuoteSelectionToken, answerFormURL: URL, in session: HFRSession
    ) async throws(QuoteError) -> QuoteComposer {
        try await multiQuote(token, answerFormURL: answerFormURL, through: session)
    }

    /// Posts `text` through `composer` (LOT-048's `reply`). Once HFR confirmed the reply, the messages of a multi-quote
    /// composer are unselected; on any error, `unconfirmed` included, the selection is kept.
    public func reply(
        _ text: String, options: [PostOption: Bool] = [:], with composer: QuoteComposer
    ) async throws(PostingError) -> PostingResult {
        let result = try await posting.reply(text, options: options, with: composer.form)
        if let selection = composer.selection {
            await composer.session.unselect(selection.numbers, of: selection.token)
        }
        return result
    }

    // MARK: - Steps

    func quote(_ message: MessageActions, through session: any QuotingSession) async throws(QuoteError) -> QuoteComposer {
        guard let url = message.quoteURL else { throw .noQuoteLink }
        let form = try await load(url, through: session)
        return QuoteComposer(form: form, prefill: try Self.prefill(of: form), selection: nil, session: session)
    }

    func multiQuote(
        _ token: QuoteSelectionToken, answerFormURL: URL, through session: any QuotingSession
    ) async throws(QuoteError) -> QuoteComposer {
        // The markers the composer's request carries: HFR prefills these messages, so these are unselected after posting.
        let numbers = await session.multiQuote(for: token, now: Date()).selectedNumbers
        guard !numbers.isEmpty else { throw .emptySelection }
        let form = try await load(answerFormURL, through: session)
        // Unselecting after the reply must touch the topic that was posted to, and only that one.
        guard form.form.field(named: "cat")?.value == token.topic.category.queryValue,
              form.form.field(named: "post")?.value == String(token.topic.topic)
        else { throw .otherTopic }
        return QuoteComposer(form: form, prefill: try Self.prefill(of: form), selection: (token, numbers), session: session)
    }

    private func load(_ url: URL, through session: any QuotingSession) async throws(QuoteError) -> PostingForm {
        do {
            return try await posting.loadForm(at: url, through: session)
        } catch {
            throw .form(error)
        }
    }

    /// The server's prefill of a reply composer; an edit, new-topic or new-MP form, or an empty textarea, holds no quote.
    private static func prefill(of form: PostingForm) throws(QuoteError) -> String {
        guard form.shape == .reply, let prefill = form.form.textareaContent else { throw .noQuote }
        return prefill
    }
}
