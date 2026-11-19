import HFRModels
import SwiftSoup

/// Namespace marker for the HFRParsing module.
/// Pure functions turning HFR HTML into HFRModels values. No networking, no storage.
public enum HFRParsing {
    public static let moduleName = "HFRParsing"

    /// Returns the trimmed text of the document `<title>`, or nil when absent.
    /// Smoke test for the SwiftSoup integration, kept for the link smoke tests (`HFRParsingTests`, and `EngineInfoTests` in the app host);
    /// the real parsers are the other types of this module.
    /// Goes through `HTMLDocumentLoader`, so only `ParsingError` can escape.
    public static func documentTitle(in html: String) throws(ParsingError) -> String? {
        let document = try HTMLDocumentLoader.document(from: html)
        guard let title = try? document.title() else { throw .malformedDocument }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
