import Foundation
import HFRModels
import HFRNetwork

/// The account session a quote composer runs in: a posting session that also keeps the multi-quote selection cookies.
///
/// `HFRSession` is the real one (LOT-042); tests script the answers and keep the cookies in a real jar.
protocol QuotingSession: PostingSession {
    /// The multi-quote selection of `token`'s topic, empty when the cookie is absent or expired at `now`.
    func multiQuote(for token: QuoteSelectionToken, now: Date) -> MultiQuoteCookie
    /// Selects or unselects `token`'s message and rewrites (or deletes) its topic's cookie.
    @discardableResult
    func toggleQuote(_ token: QuoteSelectionToken, now: Date) -> Bool
}

extension HFRSession: QuotingSession {}

extension QuotingSession {
    /// Unselects the messages `numbers` of `token`'s topic, in one actor turn; the cookie goes once nothing is left.
    ///
    /// Only these messages are unselected: one the user selected after the composer was loaded was not in its prefill,
    /// so it stays selected (a value written back after a request is compared with the session's, LESSONS 55).
    func unselect(_ numbers: [Int], of token: QuoteSelectionToken, now: Date = Date()) {
        for number in numbers {
            let message = QuoteSelectionToken(forum: token.forum, topic: token.topic, numreponse: number)
            // Read again for each number: a toggle of a message no longer selected would select it again.
            if multiQuote(for: message, now: now).contains(number) { toggleQuote(message, now: now) }
        }
    }
}
