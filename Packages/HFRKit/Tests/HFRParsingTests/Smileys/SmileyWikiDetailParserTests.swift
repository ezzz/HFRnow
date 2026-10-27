import Foundation
import Testing
@testable import HFRParsing

@Suite("Smiley wiki detail parser")
struct SmileyWikiDetailParserTests {
    @Test("R54: code, image and keywords of the entry")
    func captured() throws {
        let detail = try SmileyWikiDetailParser.parse(Fixture.capture("R54-smiley-wiki-detail-anon"))
        #expect(detail.code == "[:user3]")
        #expect(detail.imageURL?.absoluteString == "https://forum-images.hardware.fr/images/perso/user3.gif")
        #expect(detail.keywords == ["musique", "guitare", "guitariste"])
    }

    @Test("Extra spaces in the keywords are dropped; an empty value gives no keyword")
    func keywordSplitting() throws {
        let html = """
            <table><tr><th><img src="/i/a.gif"><input type="hidden" name="smiley0" value="[:a]"></th>
            <th><input type="text" name="keywords0" value="  un   deux&nbsp;trois "></th></tr></table>
            """
        #expect(try SmileyWikiDetailParser.parse(html).keywords == ["un", "deux", "trois"])
        let empty = html.replacing("  un   deux&nbsp;trois ", with: "")
        #expect(try SmileyWikiDetailParser.parse(empty).keywords.isEmpty)
    }

    @Test("Commas separate keywords too, as in the shipped Swift copies")
    func commas() throws {
        let html = "<img src=\"/a.gif\"><input name=\"smiley0\" value=\"[:a]\"><input name=\"keywords0\" value=\"a, b,c , \">"
        #expect(try SmileyWikiDetailParser.parse(html).keywords == ["a", "b", "c"])
    }

    @Test("Missing inputs are typed errors")
    func missing() {
        #expect(throws: ParsingError.missingElement("name=smiley0")) { try SmileyWikiDetailParser.parse("<p>x</p>") }
        let onlyCode = "<input name=\"smiley0\" value=\"[:a]\">"
        #expect(throws: ParsingError.missingElement("name=keywords0")) { try SmileyWikiDetailParser.parse(onlyCode) }
    }
}
