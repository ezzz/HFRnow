import Foundation
import Testing
@testable import HFRParsing

/// Expectations written from reading the captures R56a and R56b (not from the oracle), and inline pages for rules no capture
/// exercises. Inline pages state our parsing rules, not facts about HFR.
@Suite("User profile parser")
struct UserProfileParserTests {
    // MARK: - Captures

    @Test("R56a, the operator's own profile as a visitor: fields, no avatar, no smiley")
    func operatorProfile() throws {
        let profile = try UserProfileParser.parse(html: Fixture.capture("R56a-profile-operator-anon"))
        #expect(profile.pseudo == "user2")
        #expect(profile.status == "Membre")
        #expect(profile.avatarURL == nil)
        #expect(profile.personalSmilies.isEmpty)
        #expect(profile.sections.map(\.title) == ["Informations générales", "Informations relatives au forum"])
        #expect(profile.sections.map(\.fields.count) == [7, 6])
        #expect(profile.messageCount == 100)
        #expect(profile.joinDate == Date(timeIntervalSince1970: 946_681_200))
        #expect(profile.lastMessageDate == Date(timeIntervalSince1970: 946_681_200))
        #expect(profile.summary.map(\.kind) == [.messageCount, .joinDate, .lastMessageDate])
        #expect(profile.actions.map(\.kind) == [.transaction, .transaction, .privateMessage, .allMessages])
        #expect(profile.actions.allSatisfy { $0.subtitle != nil })
    }

    @Test("R56a: empty cells are empty values, 'Profile field removed.' is a value")
    func placeholders() throws {
        let profile = try UserProfileParser.parse(html: Fixture.capture("R56a-profile-operator-anon"))
        let fields = Dictionary(uniqueKeysWithValues: profile.sections.flatMap(\.fields).map { ($0.title, $0) })
        #expect(fields["Ville"]?.isPlaceholder == true)
        #expect(fields["Ville"]?.value == "")
        #expect(fields["Sexe"]?.value == "Profile field removed.")
        #expect(fields["Sexe"]?.isPlaceholder == false)
        #expect(fields["Email"]?.value == "Vous n'avez pas accès à cette information")
        #expect(fields["Date du dernier message"]?.value == "01-01-2000 à 00:00")
    }

    @Test("R56b, another member: avatar, four personal smileys, configuration link")
    func otherMemberProfile() throws {
        let profile = try UserProfileParser.parse(html: Fixture.capture("R56b-profile-other-member-anon"))
        #expect(profile.pseudo == "user3")
        #expect(profile.avatarURL?.absoluteString == "https://forum-images.hardware.fr/images/mesdiscussions-910001.jpg")
        #expect(profile.personalSmilies.map(\.code) == ["[:user3]", "[:user3:1]", "[:user3:2]", "[:user3:3]"])
        #expect(profile.personalSmilies.map(\.imageURL.path) == [
            "/images/perso/user3.gif", "/images/perso/1/user3.gif", "/images/perso/2/user3.gif", "/images/perso/3/user3.gif"
        ])
        #expect(profile.personalSmilies.map(\.title) == ["smilie perso", "user3:1", "user3:2", "user3:3"])
        #expect(profile.actions.map(\.kind) == [.configuration, .transaction, .transaction, .privateMessage, .allMessages])
        #expect(profile.actions.first?.subtitle == nil)
        #expect(profile.actions.first?.url.absoluteString == "https://forum.hardware.fr/configuration.php?config=hfr.inc&pseudo=user3")
        // The configuration row is an action, not a field.
        #expect(profile.sections.map(\.fields.count) == [7, 6])
        #expect(!profile.sections.flatMap(\.fields).contains { $0.title.contains("Configuration") })
    }

    @Test("R56b: a no-break space alone is an empty value")
    func nbspOnlyIsEmpty() throws {
        let profile = try UserProfileParser.parse(html: Fixture.capture("R56b-profile-other-member-anon"))
        let birth = try #require(profile.sections.flatMap(\.fields).first { $0.title == "Date de naissance" })
        #expect(birth.value.isEmpty)
        #expect(birth.isPlaceholder)
        #expect(profile.sections.flatMap(\.fields).first { $0.title == "Citation personnelle associée au pseudo" }?.isPlaceholder == true)
    }

    static let captures = ["R56a-profile-operator-anon", "R56b-profile-other-member-anon"]

    @Test("every URL of both captures is absolute https on the forum or its image host", arguments: captures)
    func urlsAreWebURLs(capture: String) throws {
        let profile = try UserProfileParser.parse(html: Fixture.capture(capture))
        let urls = [profile.avatarURL].compactMap { $0 }
            + profile.personalSmilies.map(\.imageURL) + profile.actions.map(\.url)
            + profile.sections.flatMap(\.fields).compactMap(\.url)
        for url in urls {
            #expect(url.scheme == "https")
            #expect(["forum.hardware.fr", "forum-images.hardware.fr"].contains(url.host(percentEncoded: false)))
        }
    }

    @Test("ids are unique within each list of both captures", arguments: captures)
    func idsAreUnique(capture: String) throws {
        let profile = try UserProfileParser.parse(html: Fixture.capture(capture))
        for ids in [profile.actions.map(\.id), profile.personalSmilies.map(\.id), profile.sections.map(\.id)] {
            #expect(Set(ids).count == ids.count)
        }
        for section in profile.sections {
            #expect(Set(section.fields.map(\.id)).count == section.fields.count)
        }
    }

    // MARK: - Inline pages

    /// A profile page with the given rows after one header.
    private static func page(_ rows: String, header: String = "Informations générales") -> String {
        """
        <html><body><table class="main"><tr class="cBackHeader"><th colspan="3">\(header)</th></tr>\(rows)</table></body></html>
        """
    }

    private static func field(_ title: String, _ value: String) -> String {
        "<tr class=\"profil\"><td class=\"profilCase2\">\(title)&nbsp;: </td><td class=\"profilCase3\">\(value)</td></tr>"
    }

    @Test("a page without any profile row is a typed error, not an empty profile")
    func notAProfile() {
        #expect(throws: ParsingError.missingElement("table.main profile rows")) {
            try UserProfileParser.parse(html: "<html><body><div class=\"hop\">Votre session a expiré</div></body></html>")
        }
        #expect(throws: ParsingError.self) { try UserProfileParser.parse(html: "") }
    }

    @Test("zero-width spaces are removed from the pseudo, not from the printed field")
    func pseudoWithoutZeroWidthSpace() throws {
        let profile = try UserProfileParser.parse(html: Self.page(Self.field("Pseudo", " abcdefghij\u{200B}klm ")))
        #expect(profile.pseudo == "abcdefghijklm")
        #expect(profile.sections.first?.fields.first?.value == "abcdefghij\u{200B}klm")
    }

    @Test("the avatar is the image of div.avatar_center only, never the first image of the row")
    func avatarIsNotTheFirstImage() throws {
        let rows = """
            <tr class="profil"><td class="profilCase3"><img src="/themes_static/images_forum/1/aide.gif" alt="" /></td>
            <td class="profilCase4"><div class="avatar_center"><img src="//forum-images.hardware.fr/images/mesdiscussions-1.jpg" alt="" />
            </div></td></tr>
            """
        let profile = try UserProfileParser.parse(html: Self.page(rows))
        #expect(profile.avatarURL?.absoluteString == "https://forum-images.hardware.fr/images/mesdiscussions-1.jpg")
    }

    @Test("only http and https URLs survive, in the avatar, smileys, fields and actions")
    func refusesOtherSchemes() throws {
        let rows = """
            <tr class="profil"><td class="profilCase4"><div class="avatar_center"><img src="javascript:alert(1)" /></div></td></tr>
            <tr class="profil"><td class="profilCase4">[:a] <img src="data:image/gif;base64,AAAA/images/perso/" alt="a" />
            [:b] <img src="https://forum-images.hardware.fr/images/perso/b.gif" alt="b" /></td></tr>
            <tr class="profil"><td class="profilCase2">Site&nbsp;: </td><td class="profilCase3">
            <a href="ftp://example.invalid/x">x</a> texte</td></tr>
            <tr class="profil"><td class="profilCase3" colspan="3"><a href="JaVaScRiPt:alert(1)">Envoyer un message privé</a></td></tr>
            <tr class="profil"><td class="profilCase3" colspan="3"><a href="http://forum.hardware.fr/x.php">Autre lien</a></td></tr>
            """
        let profile = try UserProfileParser.parse(html: Self.page(rows))
        #expect(profile.avatarURL == nil)
        #expect(profile.personalSmilies.map(\.code) == ["[:b]"])
        #expect(profile.sections.first?.fields.first?.value == "x texte")
        #expect(profile.sections.first?.fields.first?.url == nil)
        // The unsafe action is dropped; the http forum link is upgraded to https.
        #expect(profile.actions.map(\.url.absoluteString) == ["https://forum.hardware.fr/x.php"])
        #expect(profile.actions.first?.kind == .link)
    }

    @Test("action links outside https://forum.hardware.fr are dropped, field links stay external", arguments: [
        "https://evil.example/message.php", "//evil.example/x", "http://forum.hardware.fr:80/message.php",
        "https://forum.hardware.fr//evil.example/x", "https://forum.hardware.fr@evil.example/x", "/\\evil.example/x",
        "https://forum.hardware.fr:8443/x", "javascript:alert(1)"
    ])
    func hostileActionLinks(href: String) throws {
        let action = """
            <tr class="profil"><td class="profilCase3" colspan="3"><a href="\(href)">Envoyer un message privé</a></td></tr>
            """
        let configuration = Self.field("Configuration matérielle", "<a href=\"\(href)\">lien</a>")
        let website = Self.field("Site", "<a href=\"\(href)\">lien</a>")
        let profile = try UserProfileParser.parse(html: Self.page(Self.field("Pseudo", "x") + action + configuration + website))
        #expect(profile.actions.isEmpty)
        let fields = try #require(profile.sections.first?.fields)
        // A linked configuration row with a refused target is neither an action nor a field.
        #expect(!profile.actions.contains { $0.kind == .configuration })
        #expect(!fields.contains { $0.title == "Configuration matérielle" })
        let site = try #require(fields.first { $0.title == "Site" })
        #expect(site.url == nil || ["http", "https"].contains(site.url?.scheme))
    }

    @Test("a member's website stays an external http(s) field link")
    func externalFieldLink() throws {
        let profile = try UserProfileParser.parse(html: Self.page(Self.field("Site", "<a href=\"https://example.invalid/me\">me</a>")))
        #expect(profile.sections.first?.fields.first?.url?.absoluteString == "https://example.invalid/me")
    }

    @Test("relative and forum-absolute action links resolve to https://forum.hardware.fr")
    func forumActionLinks() throws {
        let rows = ["/message.php?a=1&amp;b=2", "message.php", "https://forum.hardware.fr/x.php", "http://forum.hardware.fr/y.php"]
            .map { "<tr class=\"profil\"><td class=\"profilCase3\" colspan=\"3\"><a href=\"\($0)\">Lien \($0.count)</a></td></tr>" }
            .joined()
        let urls = try UserProfileParser.parse(html: Self.page(Self.field("Pseudo", "x") + rows)).actions.map(\.url.absoluteString)
        #expect(urls == [
            "https://forum.hardware.fr/message.php?a=1&b=2", "https://forum.hardware.fr/message.php",
            "https://forum.hardware.fr/x.php", "https://forum.hardware.fr/y.php"
        ])
    }

    @Test("a smiley without printed code takes its code from the title, then the file name; spaces in the path are kept")
    func smileyCodeFallback() throws {
        let rows = """
            <tr class="profil"><td class="profilCase4">
            <img src="https://forum-images.hardware.fr/images/perso/1/u s.gif" alt="alt" title="ti" />
            <img src="https://forum-images.hardware.fr/images/perso/x.gif" /></td></tr>
            """
        let smileys = try UserProfileParser.parse(html: Self.page(rows)).personalSmilies
        #expect(smileys.map(\.code) == ["[:ti]", "x.gif"])
        #expect(smileys.map(\.title) == ["ti", nil])
        #expect(smileys.first?.imageURL.absoluteString == "https://forum-images.hardware.fr/images/perso/1/u%20s.gif")
    }

    @Test("a repeated smiley or link row appears once")
    func duplicates() throws {
        let link = """
            <tr class="profil"><td class="profilCase3" colspan="3"><a href="/m.php?a=1&amp;b=2">Envoyer un message privé</a></td></tr>
            """
        let smiley = "<tr class=\"profil\"><td class=\"profilCase4\">[:a] <img src=\"/images/perso/a.gif\" alt=\"a\" /></td></tr>"
        let profile = try UserProfileParser.parse(html: Self.page(link + link + smiley + smiley))
        #expect(profile.actions.count == 1)
        #expect(profile.actions.first?.url.absoluteString == "https://forum.hardware.fr/m.php?a=1&b=2")
        #expect(profile.personalSmilies.count == 1)
    }

    @Test("the typed figures are nil when the printed text is not a number or a valid date")
    func invalidFigures() throws {
        let rows = Self.field("Nombre de messages postés", "beaucoup")
            + Self.field("Date d'arrivée sur le forum", "31/02/2000")
            + Self.field("Date du dernier message", "hier")
        let profile = try UserProfileParser.parse(html: Self.page(rows))
        #expect(profile.messageCount == nil)
        #expect(profile.joinDate == nil)
        #expect(profile.lastMessageDate == nil)
        #expect(profile.summary.map(\.value) == ["beaucoup", "31/02/2000", "hier"])
    }

    @Test("a message count grouped by spaces is read; a header without rows is dropped")
    func groupedCountAndEmptySection() throws {
        let count = Self.field("Nombre de messages postés", "12 345")
        let html = Self.page("", header: "Vide")
            .replacing("</table>", with: "<tr class=\"cBackHeader\"><th>Suite</th></tr>\(count)</table>")
        let profile = try UserProfileParser.parse(html: html)
        #expect(profile.messageCount == 12_345)
        #expect(profile.sections.map(\.title) == ["Suite"])
        // The index in the id still counts the dropped header, as legacy.
        #expect(profile.sections.first?.id == "section|Suite|1")
    }

    @Test("titles are matched whole: a longer title containing 'Pseudo' is not the pseudo")
    func titlesAreMatchedWhole() throws {
        let rows = Self.field("Citation personnelle associée au pseudo", "bonjour") + Self.field("Pseudo", "")
        let profile = try UserProfileParser.parse(html: Self.page(rows))
        #expect(profile.pseudo == "")
        #expect(profile.sections.first?.fields.count == 2)
    }

    @Test("line breaks inside a value become newlines, runs of blanks collapse")
    func multilineValue() throws {
        let profile = try UserProfileParser.parse(html: Self.page(Self.field("Loisirs", "a  b<br /><p>c&nbsp;&nbsp;d</p>e")))
        #expect(profile.sections.first?.fields.first?.value == "a b\nc d\ne")
    }
}
