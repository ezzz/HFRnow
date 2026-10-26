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
    func firstDescendant(attribute: String = "class", matching match: AttributeMatch) -> Element? {
        descendants(attribute: attribute, matching: match).first
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
