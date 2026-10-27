import Foundation
import HFRModels
import Testing
@testable import HFRParsing

@Suite("Smiley search parser")
struct SmileySearchParserTests {
    @Test("R53a: the 'no answer' text is an empty list")
    func noResult() throws {
        #expect(try SmileySearchParser.parse(Fixture.capture("R53a-smiley-search-no-result")).isEmpty)
    }

    @Test("R53b: 657 smileys, folder N of the image matches the :N code suffix")
    func oneWord() throws {
        let smileys = try SmileySearchParser.parse(Fixture.capture("R53b-smiley-search-one-word"))
        #expect(smileys.count == 657)
        #expect(smileys[0].code == "[:user3]")
        #expect(smileys[0].url.absoluteString == "https://forum-images.hardware.fr/images/perso/user3.gif")
        #expect(smileys[2].code == "[:user5:1]")
        #expect(smileys[2].url.absoluteString == "https://forum-images.hardware.fr/images/perso/1/user5.gif")
        for smiley in smileys {
            let code = smiley.code.dropFirst(2).dropLast()   // "name" or "name:N"
            let parts = code.split(separator: ":")
            let folder = parts.count == 2 ? "\(parts[1])/" : ""
            #expect(smiley.url.absoluteString == "https://forum-images.hardware.fr/images/perso/\(folder)\(parts[0]).gif")
        }
    }

    @Test("R53c: 1010 smileys, a repeated smiley stays repeated")
    func twoWords() throws {
        let smileys = try SmileySearchParser.parse(Fixture.capture("R53c-smiley-search-two-words"))
        #expect(smileys.count == 1010)
        #expect(smileys.filter { $0.code == "[:user144]" }.count == 2)
    }

    @Test("Spaces and apostrophes in the file name survive; unusable images are skipped")
    func rawPaths() throws {
        let html = """
            <img src="https://forum-images.hardware.fr/images/perso/o'brien smile.gif" alt="[:o'brien smile]" />
            <img src="javascript:alert(1)" alt="[:evil]" />
            <img src="https://forum-images.hardware.fr/images/perso/noalt.gif" />
            <img src="" alt="[:nosrc]" />
            <img src="/images/perso/rel.gif" alt="[:rel]" />
            """
        let smileys = try SmileySearchParser.parse(html)
        #expect(smileys.map(\.code) == ["[:o'brien smile]", "[:rel]"])
        #expect(smileys[0].url.absoluteString.hasPrefix("https://forum-images.hardware.fr/images/perso/o'brien"))
        #expect(smileys[1].url.absoluteString == "https://forum.hardware.fr/images/perso/rel.gif")
    }

    @Test("A full captured page instead of the fragment is an error", arguments: ["R01-home-anon", "R03-home-logged-in-no-unread-mp"])
    func fullPage(name: String) throws {
        let html = try Fixture.capture(name)
        #expect(html.contains("<img"))
        #expect(throws: ParsingError.missingElement("img alt=smiley code")) { try SmileySearchParser.parse(html) }
    }

    @Test("Images whose alt is not a smiley code are skipped")
    func otherAlts() throws {
        let html = """
            <img src="/img/logo.gif" alt="Logo" /><img src="/p.gif" alt="[:half" /><img src="/ok.gif" alt="[:ok]" />
            """
        #expect(try SmileySearchParser.parse(html).map(\.code) == ["[:ok]"])
    }

    @Test("Neither smiley nor 'no answer' sentence: missing element", arguments: ["", "<html><body><p>Erreur</p></body></html>"])
    func unrecognised(html: String) {
        #expect(throws: ParsingError.missingElement("img alt=smiley code")) {
            try SmileySearchParser.parse(html)
        }
    }
}
