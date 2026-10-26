import HFRModels
import SwiftSoup

/// One list row: the `<tr>` it was read from and its summary.
struct ParsedTopicRow {
    /// The row element (`tr.sujet.ligne_booleen`), for cells the summary does not model.
    let element: Element
    /// The row as `TopicListRowParser` reads it.
    var summary: TopicSummary
}
