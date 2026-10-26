import SwiftSoup

/// Entry point from an HTML string to the backend's document. Internal: SwiftSoup never leaves HFRParsing (ADR 0002).
enum HTMLDocumentLoader {
    /// Parses a full page; backend failures become `ParsingError.malformedDocument`.
    static func document(from html: String) throws(ParsingError) -> Document {
        do {
            // `SwiftSoup.parse` switches to the XML parser on a leading `<?xml`; HFR pages always need HTML rules.
            return try SwiftSoup.parseHTML(html)
        } catch {
            throw .malformedDocument
        }
    }
}
