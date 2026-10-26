import Foundation

/// One message block of a topic page, as the page states it: the facts the later stages build on
/// (LOT-031 action links, LOT-032 quotes, LOT-034 content normalization), before any policy or rewriting.
///
/// Replaces the per-message part of `ParseMessagesOperation.parseData:` (`ParseMessagesOperation.m:137-475`)
/// that is neither an action link, a quote, a filter nor an avatar download.
public struct MessageBlock: Sendable, Hashable, Identifiable, Codable {
    /// Message number inside its category, from the `<a name="t<numreponse>">` anchor (the `t` dropped).
    public var numreponse: Int
    /// Author pseudo as printed in the block, without the zero-width spaces HFR inserts in long pseudos, trimmed.
    public var author: String
    /// True when the block sits in a `messagetabledel` wrapper (a deleted message placeholder; **pending capture**).
    public var isDeleted: Bool
    /// True for the "Reprise du message précédent" block that opens page 2 and later: a copy of the previous page's
    /// last message, with the same `numreponse`.
    public var isContinuation: Bool
    /// Avatar image URL, when the block shows one (`avatar_center`).
    public var avatarURL: URL?
    /// Posting date as the toolbar prints it, reduced to `dd-MM-yyyy HH:mm:ss`; empty when the toolbar has no date.
    public var dateText: String
    /// Posting instant (Europe/Paris wall-clock time resolved by `HFRDate`); nil when `dateText` is empty.
    public var postedAt: Date?
    /// Inner HTML of the content element (`div#para<numreponse>`), as the page serves it: not sanitized, not
    /// normalized. The input of LOT-034; never display it as is.
    public var contentHTML: String
    /// Edit trailer, `<pseudo> le <date>` as printed after "Message édité par"; nil when the message was never edited.
    public var editNote: String?
    /// Pseudo of the last editor, read from `editNote`.
    public var editedBy: String?
    /// Instant of the last edit, read from `editNote`.
    public var editedAt: Date?
    /// Number of messages quoting this one, from "Message cité N fois"; nil when the trailer is absent.
    public var quotedByCount: Int?
    /// Page listing the quoting messages (the `quote_only=1` link of the trailer); nil without a count.
    public var quotedByURL: URL?

    /// The message number, unique on a page except for the continuation block which repeats the previous page's last post.
    public var id: Int { numreponse }

    /// Creates a block.
    public init(
        numreponse: Int,
        author: String,
        isDeleted: Bool = false,
        isContinuation: Bool = false,
        avatarURL: URL? = nil,
        dateText: String = "",
        postedAt: Date? = nil,
        contentHTML: String,
        editNote: String? = nil,
        editedBy: String? = nil,
        editedAt: Date? = nil,
        quotedByCount: Int? = nil,
        quotedByURL: URL? = nil
    ) {
        self.numreponse = numreponse
        self.author = author
        self.isDeleted = isDeleted
        self.isContinuation = isContinuation
        self.avatarURL = avatarURL
        self.dateText = dateText
        self.postedAt = postedAt
        self.contentHTML = contentHTML
        self.editNote = editNote
        self.editedBy = editedBy
        self.editedAt = editedAt
        self.quotedByCount = quotedByCount
        self.quotedByURL = quotedByURL
    }
}
