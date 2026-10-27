import HFRModels
import SwiftSoup

/// A parsed list page with the elements its rows came from, for parsers that extend the topic list (LOT-023, LOT-024).
struct ParsedTopicList {
    /// The page as `TopicListParser.parse` returns it.
    var page: TopicListPage
    /// Rows in page order, aligned with `page.topics`; rows the parser skipped are absent from both.
    var rows: [ParsedTopicRow]
    /// The page body the rows belong to; nil for a message page. Elements of another parse of the same page are not these.
    var body: Element?
}
