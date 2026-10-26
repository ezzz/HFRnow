/// Typed failure of an HFR parser.
///
/// Payloads name what was looked for (a selector, an attribute, a field), never the page content:
/// HFR pages carry `hash_check` tokens and pseudos, and errors end up in logs.
public enum ParsingError: Error, Sendable, Equatable {
    /// The HTML backend could not read the document at all.
    case malformedDocument
    /// A required element is absent; the payload describes the search (e.g. `class=messagetable`).
    case missingElement(String)
    /// A required attribute is absent on an element that was found.
    case missingAttribute(element: String, attribute: String)
    /// A value is present but does not have the expected shape (date, number, URL…); the payload names the field.
    case invalidValue(field: String)
}
