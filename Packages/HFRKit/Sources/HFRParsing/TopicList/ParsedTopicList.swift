import HFRModels

/// A parsed list page with the elements its rows came from, for parsers that extend the topic list (LOT-023, LOT-024).
struct ParsedTopicList {
    /// The page as `TopicListParser.parse` returns it.
    var page: TopicListPage
    /// Rows in page order, aligned with `page.topics`; rows the parser skipped are absent from both.
    var rows: [ParsedTopicRow]
}
