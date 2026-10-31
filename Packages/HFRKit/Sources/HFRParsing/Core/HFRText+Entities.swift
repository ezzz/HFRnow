import SwiftSoup

extension HFRText {
    /// `text` with its HTML entities decoded, as SwiftSoup decodes a page's text; nil when SwiftSoup cannot read it.
    ///
    /// For text HFR serves outside a page: the REST API's names and titles carry entities (`&amp;` in `R57a`, LOT-057).
    public static func decodingHTMLEntities(_ text: String) -> String? {
        try? Entities.unescape(text)
    }
}
