import Foundation

/// One message of a topic page; policy (blacklist, filters) is applied later by the app.
public struct Message: Sendable, Hashable, Identifiable, Codable {
    /// Stable identity: the message number (`numreponse`), unique in its category and so on its page.
    /// Use `TopicPage.postID(of:)` for the key that is unique across topics.
    public var id: Int
    /// Author pseudo.
    public var author: String
    /// True for a deleted message placeholder.
    public var isDeleted: Bool
    /// Avatar image URL.
    public var avatarURL: URL?
    /// Date as HFR prints it (`dd-MM-yyyy HH:mm:ss`, Europe/Paris), kept as text.
    public var dateText: String
    /// Normalised content.
    public var content: MessageContent
    /// Quote blocks in document order.
    public var quotes: [MessageQuote]
    /// Edit trailer text, `<pseudo> le <date>`; nil when never edited.
    public var editNote: String?
    /// How many times the message was quoted, from "Message cité N fois"; nil when not shown.
    public var quotedByCount: Int?
    /// Link behind the "quoted N times" trailer.
    public var quotedByURL: URL?
    /// Action links.
    public var actions: MessageActions

    /// Creates a message.
    public init(
        id: Int,
        author: String,
        isDeleted: Bool = false,
        avatarURL: URL? = nil,
        dateText: String = "",
        content: MessageContent,
        quotes: [MessageQuote] = [],
        editNote: String? = nil,
        quotedByCount: Int? = nil,
        quotedByURL: URL? = nil,
        actions: MessageActions = MessageActions()
    ) {
        self.id = id
        self.author = author
        self.isDeleted = isDeleted
        self.avatarURL = avatarURL
        self.dateText = dateText
        self.content = content
        self.quotes = quotes
        self.editNote = editNote
        self.quotedByCount = quotedByCount
        self.quotedByURL = quotedByURL
        self.actions = actions
    }
}
