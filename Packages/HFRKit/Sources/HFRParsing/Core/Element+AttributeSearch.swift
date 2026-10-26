import SwiftSoup

/// Descendant lookups with legacy `HTMLNode` semantics (`HTMLNode.m:105-139, 232-298`).
///
/// Like the legacy methods, the search starts at the children: the receiver itself is never returned,
/// and results come in document order (pre-order, depth first), which is what `findChild…` returned first.
extension Element {
    /// All descendants whose `attribute` is present and satisfies `match`, in document order.
    func descendants(attribute: String = "class", matching match: AttributeMatch) -> [Element] {
        let all: Elements
        do {
            all = try getAllElements()
        } catch {
            return []
        }
        return all.array().dropFirst().filter { element in
            guard element.hasAttr(attribute), let value = try? element.attr(attribute) else { return false }
            return match.matches(value)
        }
    }

    /// First descendant whose `attribute` satisfies `match` (legacy `findChildWithAttribute:…`), or nil.
    ///
    /// Walks the subtree in document order and stops at the first match, instead of materializing it like
    /// `descendants`: on a 55-row list page (R04) a whole-body search cost about 5 ms in release, and most list
    /// header lookups hit early (LOT-022).
    func firstDescendant(attribute: String = "class", matching match: AttributeMatch) -> Element? {
        var pending = Array(children().array().reversed())
        while let element = pending.popLast() {
            if element.hasAttr(attribute), let value = try? element.attr(attribute), match.matches(value) {
                return element
            }
            pending.append(contentsOf: element.children().array().reversed())
        }
        return nil
    }

    /// Like `firstDescendant`, but a missing element is a typed error naming the search.
    func requiredDescendant(attribute: String = "class", matching match: AttributeMatch) throws(ParsingError) -> Element {
        guard let element = firstDescendant(attribute: attribute, matching: match) else {
            throw .missingElement(match.description(attribute: attribute))
        }
        return element
    }

    /// Value of `attribute`, or a typed error when the attribute is absent.
    func requiredAttribute(_ attribute: String) throws(ParsingError) -> String {
        guard hasAttr(attribute), let value = try? attr(attribute) else {
            throw .missingAttribute(element: tagName(), attribute: attribute)
        }
        return value
    }
}
