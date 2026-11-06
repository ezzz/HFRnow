import SwiftSoup

/// Entry point from an XML string to SwiftSoup's tree, for the two documents `aq.super-h.fr` serves (LOT-028).
/// Internal: SwiftSoup never leaves HFRParsing (ADR 0002).
enum AQXMLDocument {
    /// Parses an XML answer with SwiftSoup's XML rules (names keep their case, CDATA is text, entities in attributes are decoded).
    ///
    /// `HTMLDocumentLoader` cannot be used: HTML rules would drop `<link>`'s text and lowercase `pseudoInitiateur`.
    static func document(from xml: String) throws(ParsingError) -> Document {
        do {
            return try SwiftSoup.parse(xml, "", Parser.xmlParser())
        } catch {
            throw .malformedDocument
        }
    }
}
