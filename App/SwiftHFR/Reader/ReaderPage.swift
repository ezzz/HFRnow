import Foundation
import HFRModels

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
    /// The topic's poll (LOT-026) when the page has one that `PollParser` reads; nil otherwise, also when the poll's shape is
    /// not one it handles (a poll that cannot be read never fails the page). Holds the voting form's hidden fields, token
    /// included: only `PollVoteFlow` reads them.
    var poll: Poll?
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

    /// Unique on a page: the continuation block repeats the previous page's last number.
    var id: String { isContinuation ? "continuation-\(numreponse)" : "t\(numreponse)" }
}
