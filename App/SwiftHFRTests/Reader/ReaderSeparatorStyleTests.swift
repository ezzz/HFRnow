import Foundation
@testable import SwiftHFR
import Testing

/// The read / unread line of the reader sheet (#807): legacy's thickness per style and the « Nouveau » chip on that line only.
struct ReaderSeparatorStyleTests {
    private func css() throws -> String {
        let url = try #require(Bundle.main.url(forResource: "reader", withExtension: "css"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// The declarations of the first rule whose selector is exactly `selector`, whitespace collapsed.
    private func rule(_ selector: String, in css: String) throws -> String {
        let open = try #require(css.range(of: "\n\(selector) {"), "no rule for \(selector)")
        let close = try #require(css[open.upperBound...].range(of: "}"))
        return css[open.upperBound..<close.lowerBound].split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    @Test func modernIsTwoPixelsSolidAndClassicOnePixelDashed() throws {
        let sheet = try css()
        #expect(try rule(".style-modern .separator1", in: sheet).contains("border-top: 2px solid var(--separator-new)"))
        #expect(try rule(".separator1", in: sheet).contains("border-top: 1px dashed var(--separator-new)"))
    }

    @Test func theLineIsStrongerThanTheQuietSeparator() throws {
        let sheet = try css()
        #expect(!(try rule(".separator1", in: sheet)).contains("var(--separator)"))
        #expect(sheet.contains("--separator-new: color-mix(in srgb, var(--text) 40%, transparent)"))
    }

    @Test func theNouveauChipIsGeneratedContentOfTheLineOnly() throws {
        let sheet = try css()
        #expect(try rule(".separator1::after", in: sheet).contains("content: \"Nouveau\""))
        #expect(sheet.components(separatedBy: "content: \"Nouveau\"").count == 2, "one chip rule, on the line only")
    }

    @Test func noScriptDrawsTheChip() throws {
        // The chip is CSS: the line's markup stays the empty div the legacy builder wrote, the CSP keeps `script-src 'none'`.
        let html = TopicHTMLBuilder.document(for: readerPage(page: 3), token: 1, separatorAfter: 300)
        #expect(html.contains("<div class=\"separator1\"></div>"))
        #expect(!html.contains("Nouveau"), "the word lives in the stylesheet, never in the page")
    }
}
