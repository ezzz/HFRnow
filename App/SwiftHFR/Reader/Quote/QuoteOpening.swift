import Foundation
import HFRClient
import HFRModels
import HFRNetwork

// Port of HFRswift/Swift/MessagesView.swift (`openQuoteComposer`, `openTextQuoteComposer`, the `quoter` cookie toggles,
// :1852-1945, :4144-4195) @ 21173e7 and HFRswift/Swift/ReplyService.swift:767-841 (`fetchQuoteTemplate`) @ 2440d79. Differences:
// the quote engine is LOT-049's (`QuoteFlow`, in the current account's session), the selection cookie is LOT-042's, and the selection
// is released after HFR's confirmation of the reply (legacy never cleared it: it expired after one hour, p. 505).
/// The messages selected for a multi-quote, and the quotes the engine fetches: the reader's quoting seam (`LiveQuoter` in the app,
/// a scripted double in tests).
protocol QuoteOpening: Sendable {
    /// The messages of `token`'s topic that are selected, in the order they were selected. The selection lives in the account
    /// session, an actor: reading it is asynchronous.
    func selectedNumbers(for token: QuoteSelectionToken) async -> [Int]
    /// Selects or unselects `token`'s message; returns whether it is selected now.
    func toggle(_ token: QuoteSelectionToken) async -> Bool
    /// HFR's quote of one message (`QuoteFlow.quote`): the reply composer's prefill. The selection is left alone.
    func quote(_ message: MessageActions) async throws(QuoteError) -> String
    /// HFR's prefill for the whole selection of `token`'s topic, its blocks in topic order, and what to release once the reply
    /// that holds them is posted.
    func selectionQuote(_ token: QuoteSelectionToken, answerFormURL: URL) async throws(QuoteError) -> ReplyQuote
    /// Unselects the messages `release` names that the text just posted still quotes (and only those).
    func release(_ release: QuoteRelease, postedText: String) async
}

/// The selection a multi-quote reply stands for: unselected once HFR confirmed the reply that quotes it.
struct QuoteRelease: Equatable, Sendable {
    /// Any message of the topic: it names the selection's cookie.
    let token: QuoteSelectionToken
    /// The messages selected when the composer's prefill was asked for.
    let numbers: [Int]
}

/// What the composer opens with: text merged into the topic's draft and, for a multi-quote, what to release after the send.
struct ReplyQuote: Equatable, Sendable {
    /// HFR's quote blocks, as served (selection quotes narrowed by `QuoteSelectionFormatter`).
    let text: String
    /// Set for a multi-quote only: a single quote never touches the selection.
    var release: QuoteRelease?
}

/// LOT-049's quote engine over the current account's session.
struct LiveQuoter: QuoteOpening {
    /// The current account's session (`AppEnvironment.session`): it holds the selection cookies.
    let session: HFRSession
    private let flow = QuoteFlow()

    /// Creates a quoter on `session`.
    init(session: HFRSession) {
        self.session = session
    }

    func selectedNumbers(for token: QuoteSelectionToken) async -> [Int] {
        await session.multiQuote(for: token).selectedNumbers
    }

    func toggle(_ token: QuoteSelectionToken) async -> Bool {
        await session.toggleQuote(token)
    }

    func quote(_ message: MessageActions) async throws(QuoteError) -> String {
        try await flow.quote(message, in: session).prefill
    }

    func selectionQuote(_ token: QuoteSelectionToken, answerFormURL: URL) async throws(QuoteError) -> ReplyQuote {
        let composer = try await flow.multiQuote(token, answerFormURL: answerFormURL, in: session)
        // The messages HFR prefilled are the ones to release, not a selection read around the request: a message toggled
        // meanwhile is in the posted text or it is not, and the prefill says which.
        let numbers = Self.quotedNumbers(in: composer.prefill).sorted()
        return ReplyQuote(text: MultiQuoteOrder.topicOrder(composer.prefill), release: QuoteRelease(token: token, numbers: numbers))
    }

    func release(_ release: QuoteRelease, postedText: String) async {
        let quoted = Self.quotedNumbers(in: postedText)
        // One actor turn (LESSONS 55): a message the user unselected meanwhile is not selected again.
        await session.unselectQuotes(release.numbers.filter(quoted.contains), of: release.token)
    }

    /// The messages a text quotes: the first number of each `[quotemsg=<numreponse>,<ref>,<author>]`. The rule of
    /// `QuoteFlow.reply` (LOT-049), which posts through the form it fetched itself; the composer posts through a fresh one.
    static func quotedNumbers(in text: String) -> Set<Int> {
        Set(text.matches(of: /\[quotemsg=([0-9]+),[0-9]+,[0-9]+\]/.ignoresCase()).compactMap { Int($0.output.1) })
    }
}
