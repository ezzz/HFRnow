import Foundation
import Testing
@testable import HFRParsing

@Suite("Own smileys parser (#414)")
struct OwnSmileysParserTests {
    @Test("R601a: the six created smileys in order, codes from the alt, images under /images/perso/")
    func owner() throws {
        let smileys = try OwnSmileysParser.parse(Fixture.capture("R601a-profile-edit-page5-personal-smileys"))
        #expect(smileys.map(\.code) == ["[:user1]", "[:user1:1]", "[:user1:2]", "[:user1:3]", "[:user1:4]", "[:user1:5]"])
        #expect(smileys.first?.imageURL.absoluteString == "https://forum-images.hardware.fr/images/perso/user1.gif")
        #expect(smileys.last?.imageURL.absoluteString == "https://forum-images.hardware.fr/images/perso/5/user1.gif")
    }

    @Test("R55-p5: a member with none has only the management link: an empty list, not an error")
    func none() throws {
        #expect(try OwnSmileysParser.parse(Fixture.capture("R55-p5-profile-edit-page5")).isEmpty)
    }

    @Test("The favourites row below is not read as the member's own smileys")
    func favouritesRowIsNotRead() throws {
        let smileys = try OwnSmileysParser.parse(Fixture.capture("R601a-profile-edit-page5-personal-smileys"))
        #expect(!smileys.contains { $0.code == "[:user3]" || $0.code == "[:user4]" })
    }

    @Test("A page without the row is an error, never an empty list (a login wall must not read as « no smileys »)")
    func otherPage() {
        #expect(throws: ParsingError.self) { try OwnSmileysParser.parse("<html><body><p>Connectez-vous</p></body></html>") }
    }

    @Test("A repeated code is listed once, and an image outside /images/perso/ or without an alt is ignored")
    func filters() throws {
        let html = """
        <table><tr class="profil"><td class="profilCase2"><b>Smilies persos&nbsp;:</b></td><td class="profilCase3">
        <img src="https://forum-images.hardware.fr/images/perso/a.gif" alt="a" /> [:a]
        <img src="https://forum-images.hardware.fr/images/perso/a.gif" alt="a" /> [:a]
        <img src="https://forum-images.hardware.fr/images/perso/1/b.gif" alt="b:1" /> [:b:1]
        <img src="https://forum-images.hardware.fr/icones/smilies/x.gif" alt="x" />
        <img src="https://forum-images.hardware.fr/images/perso/c.gif" />
        </td></tr></table>
        """
        #expect(try OwnSmileysParser.parse(html).map(\.code) == ["[:a]", "[:b:1]"])
    }
}
