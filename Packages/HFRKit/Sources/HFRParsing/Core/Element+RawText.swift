import SwiftSoup

/// Text extraction that keeps whitespace as written, like the legacy `HTMLNode` accessors.
///
/// SwiftSoup's `text()` collapses runs of whitespace; legacy `allContents` and `contents` did not
/// (`SuperHFRplus/Vendor/HTMLParser/HTMLNode.m`), and the oracle compares their output. Entities are decoded either way.
extension Element {
    /// Every descendant text node, concatenated in document order (legacy `allContents`).
    var rawText: String {
        var text = ""
        appendRawText(of: self, to: &text, recursive: true)
        return text
    }

    /// The element's own text nodes only, children elements skipped (the date of a last-post link, before its `<b>` author).
    var ownRawText: String {
        var text = ""
        appendRawText(of: self, to: &text, recursive: false)
        return text
    }

    private func appendRawText(of element: Element, to text: inout String, recursive: Bool) {
        for node in element.getChildNodes() {
            if let textNode = node as? TextNode {
                text += textNode.getWholeText()
            } else if recursive, let child = node as? Element {
                appendRawText(of: child, to: &text, recursive: true)
            }
        }
    }
}
