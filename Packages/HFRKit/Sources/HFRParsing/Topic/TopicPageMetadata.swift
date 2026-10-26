import Foundation
import HFRModels

/// Page-level data of a topic page: everything but the messages and the poll (LOT-033).
///
/// The fields line up with `TopicPage` (HFRModels), which the caller assembles from this value, the messages (LOT-030)
/// and the poll (LOT-026). Form fields hold the `hash_check` token: the descriptions and the reflection print counts only,
/// and the type is deliberately not `Codable` so a token cannot be persisted by accident.
public struct TopicPageMetadata: Sendable, Hashable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// Category and topic numbers, read from the page's forms first and from the page URL otherwise; nil when neither has both.
    public var topicID: TopicID?
    /// Title of the topic, trimmed; empty when the page has none (for instance a private conversation deleted by its owner).
    public var title: String
    /// Page the URL asks for (1 when the URL names none). Taken from the URL only, like legacy: it can exceed `maxPage`.
    public var currentPage: Int
    /// Number of pages: the highest page number of the pager, or 1 when the page has no pager (single page topic).
    public var maxPage: Int
    /// Page that holds the answer form; nil when the page has none (closed topic, logged out, conversation deleted).
    public var answerFormURL: URL?
    /// Hidden inputs of the quick-answer form `hop`; empty when the page has none. Contains `hash_check`: never log it.
    public var answerFormFields: [String: String]
    /// True when the page has a link whose `href` contains `nonlu` (the "mark as unread" link, present on private conversations).
    public var isUnreadable: Bool
    /// True when the page has a poll block (`div.sondage`). The poll itself is `PollParser`'s job (LOT-026).
    public var hasPoll: Bool
    /// Inputs of the in-topic search form that legacy kept; nil when the page has no such form. Contains `hash_check`.
    public var searchFormFields: [String: String]?

    /// Creates a value; used by the parser and by tests.
    public init(
        topicID: TopicID? = nil,
        title: String = "",
        currentPage: Int = 1,
        maxPage: Int = 1,
        answerFormURL: URL? = nil,
        answerFormFields: [String: String] = [:],
        isUnreadable: Bool = false,
        hasPoll: Bool = false,
        searchFormFields: [String: String]? = nil
    ) {
        self.topicID = topicID
        self.title = title
        self.currentPage = currentPage
        self.maxPage = maxPage
        self.answerFormURL = answerFormURL
        self.answerFormFields = answerFormFields
        self.isUnreadable = isUnreadable
        self.hasPoll = hasPoll
        self.searchFormFields = searchFormFields
    }

    /// Summary that never prints the form fields (they hold the `hash_check` token).
    public var description: String {
        "TopicPageMetadata(\(title), page \(currentPage)/\(maxPage), "
            + "\(answerFormFields.count + (searchFormFields?.count ?? 0)) form fields, values redacted)"
    }

    /// Same as `description`.
    public var debugDescription: String { description }

    /// Reflection (`dump`, debugger) hides the form field values too.
    public var customMirror: Mirror {
        Mirror(self, children: [
            "topicID": topicID as Any,
            "title": title,
            "currentPage": currentPage,
            "maxPage": maxPage,
            "answerFormURL": answerFormURL as Any,
            "answerFormFields": "\(answerFormFields.count) fields, values redacted",
            "isUnreadable": isUnreadable,
            "hasPoll": hasPoll,
            "searchFormFields": searchFormFields.map { "\($0.count) fields, values redacted" } as Any
        ], displayStyle: .struct)
    }
}
