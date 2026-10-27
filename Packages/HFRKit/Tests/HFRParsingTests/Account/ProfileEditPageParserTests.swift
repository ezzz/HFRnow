import Foundation
import Testing
@testable import HFRParsing

@Suite("Profile edit page parser")
struct ProfileEditPageParserTests {
    @Test(
        "Pages 1, 3 and 5 all expose the token; user2 has no avatar",
        arguments: ["R55-p1-profile-edit-page1", "R55-p3-profile-edit-page3", "R55-p5-profile-edit-page5"]
    )
    func captured(name: String) throws {
        let page = try ProfileEditPageParser.parse(Fixture.capture(name))
        #expect(page.hashCheck == "REDACTED")
        #expect(page.avatarURL == nil)
    }

    @Test("R55-p5 facts: validation form, hidden page field, avatar row offers creation only")
    func page5Facts() throws {
        let html = try Fixture.capture("R55-p5-profile-edit-page5")
        #expect(html.contains("<form name=\"ONSENFOU\" action=\"editprofil_validation.php?config=hfr.inc\" method=\"post\">"))
        #expect(html.contains("<input type=\"hidden\" name=\"page\" value=\"5\" />"))
        #expect(html.contains("Créer un avatar"))
        #expect(html.matches(of: /name="hash_check"/).count == 2)
    }

    @Test("R55-p3 fact: posts per page is the text input topicpp")
    func page3Facts() throws {
        let html = try Fixture.capture("R55-p3-profile-edit-page3")
        #expect(html.contains("<input type=\"text\" name=\"topicpp\""))
    }

    @Test("R55-p5u1 (account with an avatar): the real avatar, not the icons or smileys that follow")
    func capturedAvatar() throws {
        let html = try Fixture.capture("R55-p5u1-profile-edit-page5-avatar")
        let page = try ProfileEditPageParser.parse(html)
        #expect(page.hashCheck == "REDACTED")
        #expect(page.avatarURL?.absoluteString == "https://forum-images.hardware.fr/images/mesdiscussions-900001.jpg")
        // Facts of the avatar row: the image comes before the "Modifier / Effacer votre avatar" links; personal smileys follow.
        #expect(html.contains("Modifier votre avatar"))
        #expect(html.contains("images/perso/user1.gif"))
    }

    @Test("Hand-written avatar cells: relative or absolute source, and never another row's image")
    func avatar() throws {
        let row = { (cell: String) in
            """
            <input type="hidden" name="hash_check" value="0123456789abcdef0123456789abcdef" />
            <table><tr class="profil"><td class="profilCase1">&nbsp;</td><td class="profilCase2"><b>Mon&nbsp;avatar&nbsp;:</b></td>
            <td class="profilCase3"><img src="/other.gif"></td></tr>
            <tr class="profil"><td class="profilCase2"><b>Avatar&nbsp;:</b></td><td class="profilCase3">\(cell)</td></tr>
            <tr class="profil"><td class="profilCase2">Autre</td><td class="profilCase3"><img src="/later.gif"></td></tr></table>
            """
        }
        let relative = try ProfileEditPageParser.parse(row("<a href=\"x\"><img src=\"/avatars/u1.png\" alt=\"\"></a>"))
        #expect(relative.hashCheck == "0123456789abcdef0123456789abcdef")
        #expect(relative.avatarURL?.absoluteString == "https://forum.hardware.fr/avatars/u1.png")
        let absolute = try ProfileEditPageParser.parse(row("<img src=\"https://forum-images.hardware.fr/a.gif\">"))
        #expect(absolute.avatarURL?.absoluteString == "https://forum-images.hardware.fr/a.gif")
        // No image in the avatar cell: nil, not the next row's image (legacy regex would return it).
        #expect(try ProfileEditPageParser.parse(row("<a href=\"upload.php\">Créer un avatar</a>")).avatarURL == nil)
        #expect(try ProfileEditPageParser.parse(row("<img src=\"javascript:alert(1)\">")).avatarURL == nil)
    }

    @Test("First non-empty token wins; none or all empty is an error")
    func tokens() throws {
        let page = try ProfileEditPageParser.parse("<input name=\"hash_check\" value=\"\"><input name=\"hash_check\" value=\" tok \">")
        #expect(page.hashCheck == "tok")
        #expect(throws: ParsingError.invalidValue(field: "hash_check")) {
            try ProfileEditPageParser.parse("<input name=\"hash_check\" value=\"\">")
        }
        #expect(throws: ParsingError.missingElement("input name=hash_check")) {
            try ProfileEditPageParser.parse("<p>Identification</p><div name=\"hash_check\">x</div>")
        }
    }
}
