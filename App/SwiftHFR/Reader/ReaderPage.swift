import Foundation
import HFRModels
import HFRParsing

/// One topic page as the reader shows it: page facts (LOT-033), message blocks (LOT-030) and their normalized content
/// (LOT-034). Holds no reply form field or token: the only reply entry is the answer link, which the composer fetches (LOT-084).
/// The poll's voting form (LOT-136) carries its hidden fields, `hash_check` included; only `PollVoteFlow` reads them.
struct ReaderPage: Equatable, Sendable {
    /// Category and topic numbers, read from the page; nil when the page does not give them.
    var topicID: TopicID?
    /// Topic title; empty when the page has none.
    var title: String
    /// Page shown, 1-based.
    var currentPage: Int
    /// Number of pages, at least 1.
    var maxPage: Int
    /// Messages in page order.
    var messages: [ReaderMessage]
    /// HFR's own message when it served a notice instead of messages (a `.hop` page); nil otherwise.
    var notice: String?
    /// The reply composer's page (`#repondre_form`'s link, `https` on the forum host, LOT-033); nil when the page offers no
    /// answer form (logged out, locked topic).
    var answerURL: URL?
    /// Final URL of the page after HFR's redirects, forum origin only (the permalink of a message is this plus `#t<n>`);
    /// nil when it is not a forum `https` URL.
    var pageURL: URL?
    /// The topic's poll (LOT-026) when the page has one that `PollParser` reads; nil otherwise, also when the poll's shape is
    /// not one it handles (a poll that cannot be read never fails the page). Holds the voting form's hidden fields, token
    /// included: only `PollVoteFlow` reads them.
    var poll: Poll?
    /// The private conversation's `nonlu.php` link (LOT-058, `https` on the forum, the page's own header link, never a member's);
    /// nil on a topic page. A state-changing GET: only `TopicFlagActions.markUnread` follows it.
    var markUnreadURL: URL?
}

/// One message of a `ReaderPage`.
struct ReaderMessage: Equatable, Sendable, Identifiable {
    /// Message number (`numreponse`).
    var numreponse: Int
    /// Author pseudo, untrusted text.
    var author: String
    /// Deleted message placeholder.
    var isDeleted: Bool
    /// The copy of the previous page's last message that opens page 2 and later.
    var isContinuation: Bool
    /// Avatar URL, untrusted; loaded through the image policy.
    var avatarURL: URL?
    /// Date as HFR prints it, untrusted text.
    var dateText: String
    /// Edit trailer `<pseudo> le <date>`, untrusted text.
    var editNote: String?
    /// "Message cité N fois".
    var quotedByCount: Int?
    /// Sanitized content and typed lists (ADR 0006).
    var content: MessageContent
    /// The quote blocks of `content`, in document order (LOT-032): the visibility policy classes them by author (LOT-117).
    var quotes: [MessageQuote] = []
    /// The action links of the message's toolbar (LOT-031); nothing offered when HFR gave none (logged out).
    var actions = MessageActions()

    /// Unique on a page: the continuation block repeats the previous page's last number.
    var id: String { isContinuation ? "continuation-\(numreponse)" : "t\(numreponse)" }

    /// The quotes of `content`, read once when the page is built so the builder stays string work. Only a backend failure
    /// throws; the message is then shown without quote styling rather than failing the page.
    static func quotes(of content: MessageContent) -> [MessageQuote] {
        guard content.html.contains("<table") else { return [] }
        return (try? MessageQuoteAnalyzer.quotes(inContentHTML: content.html)) ?? []
    }
}
