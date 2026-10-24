import HFRModels
import SwiftSoup

/// Namespace marker for the HFRParsing module.
/// Pure functions turning HFR HTML into HFRModels values. No networking, no storage.
public enum HFRParsing {
    public static let moduleName = "HFRParsing"

    /// Returns the trimmed text of the document `<title>`, or nil when absent.
    /// Smoke test for the SwiftSoup integration; replaced by real parsers in Phase 3.
    public static func documentTitle(in html: String) throws -> String? {
        let title = try SwiftSoup.parse(html).title()
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
