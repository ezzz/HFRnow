import Testing
@testable import HFRParsing

@Suite("Selector helpers with legacy matching")
struct AttributeSearchTests {
    static let html = """
        <html><body>
        <table class="main">
          <tr class="sujet ligne_booleen cBackCouleurTab1"><td class="sujetCase1 cBackCouleurTab1">a</td>
            <td class="sujetCase10">b</td><td class="left">c</td><td class="left nav">d</td></tr>
          <tr class="sujet ligne_booleen ligne_sticky"><td class="sujetCase1">e</td><td id="x" data-k="v">f</td></tr>
        </table>
        </body></html>
        """

    @Test("Exact compares the whole attribute value")
    func exact() throws {
        let table = try #require(try HTMLDocumentLoader.document(from: Self.html).select("table.main").first())
        #expect(table.descendants(matching: .exact("left")).map { $0.ownText() } == ["c"])
        #expect(table.descendants(matching: .exact("sujetCase1")).map { $0.ownText() } == ["e"])
    }

    @Test("Contains is a substring match, so `sujetCase1` also finds `sujetCase10`")
    func contains() throws {
        let table = try #require(try HTMLDocumentLoader.document(from: Self.html).select("table.main").first())
        #expect(table.descendants(matching: .contains("sujetCase1")).map { $0.ownText() } == ["a", "b", "e"])
        #expect(table.descendants(matching: .contains("ligne_booleen")).count == 2)
    }

    @Test("Class token matches one whitespace-separated class")
    func classToken() throws {
        let table = try #require(try HTMLDocumentLoader.document(from: Self.html).select("table.main").first())
        #expect(table.descendants(matching: .classToken("left")).map { $0.ownText() } == ["c", "d"])
        #expect(table.descendants(matching: .classToken("sujetCase1")).map { $0.ownText() } == ["a", "e"])
        #expect(table.descendants(matching: .classToken("ligne")).isEmpty)
        #expect(AttributeMatch.classToken("left").matches("left\u{0C}nav"))
        #expect(!AttributeMatch.classToken("left").matches("x\u{00A0}left"))   // HTML splits on ASCII whitespace only
    }

    @Test("The receiver itself is never returned and order is document order")
    func excludesSelf() throws {
        let table = try #require(try HTMLDocumentLoader.document(from: Self.html).select("table.main").first())
        #expect(table.descendants(matching: .exact("main")).isEmpty)
        #expect(table.firstDescendant(matching: .contains("sujet ligne_booleen"))?.hasClass("ligne_sticky") == false)
    }

    @Test("Other attributes and missing attributes")
    func otherAttributes() throws {
        let table = try #require(try HTMLDocumentLoader.document(from: Self.html).select("table.main").first())
        #expect(table.firstDescendant(attribute: "data-k", matching: .exact("v"))?.ownText() == "f")
        #expect(table.descendants(attribute: "data-missing", matching: .contains("")).isEmpty)
    }

    @Test("Required lookups throw typed errors naming the search")
    func requiredLookups() throws {
        let table = try #require(try HTMLDocumentLoader.document(from: Self.html).select("table.main").first())
        #expect(throws: ParsingError.missingElement("class=nope")) {
            try table.requiredDescendant(matching: .exact("nope"))
        }
        #expect(throws: ParsingError.missingElement("class*=nope")) {
            try table.requiredDescendant(matching: .contains("nope"))
        }
        let cell = try table.requiredDescendant(attribute: "id", matching: .exact("x"))
        #expect(try cell.requiredAttribute("data-k") == "v")
        #expect(throws: ParsingError.missingAttribute(element: "td", attribute: "href")) {
            try cell.requiredAttribute("href")
        }
    }

    /// SwiftSoup's `parse` switches to its XML parser when the input starts with `<?xml`; pages must keep HTML rules.
    @Test("A page starting with an XML declaration is still built as HTML")
    func xmlDeclarationKeepsHTMLRules() throws {
        let html = #"<?xml version="1.0" encoding="UTF-8"?><table class="main"><tr><td class="left">a<td class="left">b</table>"#
        let table = try #require(try HTMLDocumentLoader.document(from: html).select("table.main").first())
        let cells = table.descendants(matching: .exact("left"))
        #expect(cells.count == 2)
        #expect(cells.allSatisfy { $0.parent()?.tagName() == "tr" })
    }
}
