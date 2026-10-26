import SwiftSoup

/// Structural view of an HTML fragment for differential tests: the oracle's `dicoHTML` is libxml2's serialization
/// (`<br>` for `<br />`, added newlines, attributes in source order: LOT-003 Q32), so bytes are never compared.
/// Two fragments have the same shape when their visible text and their element sequence, with the attributes
/// that carry data (`href`, `src`, `alt`, `title`, `id`, `style`), are equal.
///
/// `class` is left out on purpose: the oracle content was serialized **after** legacy rewrote `oldcitation` to `citation`
/// and marked video links `embedvideo` (with `hrefemb`/`hreftxt`), which LOT-032 and LOT-035 own.
/// Empty `<p></p>` elements are left out too: HFR closes its paragraphs after a `<div style="clear: both;">`, and the
/// HTML5 tree builder (SwiftSoup) turns that stray `</p>` into an empty paragraph where libxml2 dropped it.
/// Formatting elements other than `a` (`strong`, `b`, `em`, `u`…) are left out as well: on mis-nested markup such as
/// `<span><strong>x</span></strong>` (R20 message 0) the HTML5 adoption agency reopens the element where libxml2
/// only closes it; the text and every data-carrying element still have to match.
struct HTMLShape: Equatable, CustomStringConvertible {
    /// `tag[attr=value …]` per element, in document order.
    var elements: [String]
    /// Whitespace-normalized text of the fragment.
    var text: String

    static let comparedAttributes = ["href", "src", "alt", "title", "id", "style"]
    /// HTML5 "formatting" elements without `a`, which carries the `href` the shape must keep.
    static let formattingTags: Set<String> = ["b", "big", "code", "em", "font", "i", "nobr", "s", "small", "strike", "strong", "tt", "u"]

    /// Shape of the children of `root`.
    init(children root: Element) throws {
        text = try root.text()
        elements = try root.getAllElements().array().dropFirst().filter { element in
            !Self.formattingTags.contains(element.tagName()) && (element.tagName() != "p" || element.childNodeSize() > 0)
        }.map { element in
            let attributes = Self.comparedAttributes.compactMap { name -> String? in
                guard element.hasAttr(name), let value = try? element.attr(name) else { return nil }
                // libxml2 percent-encodes the spaces of an `href` when serializing (`http://G3Ferrari / Optima`, R20 message 0).
                return "\(name)=\(value.removingPercentEncoding ?? value)"
            }
            return "\(element.tagName())[\(attributes.joined(separator: " "))]"
        }
    }

    /// Shape of a fragment parsed as the body of a document.
    init(fragment: String) throws {
        let document = try SwiftSoup.parseHTML(fragment)
        guard let body = document.body() else { throw Fixture.Missing(path: "fragment body") }
        try self.init(children: body)
    }

    /// Shape of the inside of the single element that `outerHTML` serializes (the oracle's `<div id="para…">…</div>`).
    init(insideOf outerHTML: String) throws {
        let document = try SwiftSoup.parseHTML(outerHTML)
        guard let wrapper = document.body()?.children().first else { throw Fixture.Missing(path: "oracle wrapper") }
        try self.init(children: wrapper)
    }

    var description: String {
        "text: \(text.prefix(120))\nelements: \(elements.prefix(12).joined(separator: " "))"
    }

    /// Where two shapes first differ, for test output.
    func firstDifference(from other: HTMLShape) -> String {
        if text != other.text {
            let common = zip(text, other.text).prefix { $0 == $1 }.count
            return "text differs at \(common): «\(text.dropFirst(common).prefix(60))» vs «\(other.text.dropFirst(common).prefix(60))»"
        }
        let common = zip(elements, other.elements).prefix { $0 == $1 }.count
        let mine = elements.dropFirst(max(0, common - 2)).prefix(6).joined(separator: " ")
        let theirs = other.elements.dropFirst(max(0, common - 2)).prefix(6).joined(separator: " ")
        return "elements differ at \(common): «\(mine)» vs «\(theirs)»"
    }
}
