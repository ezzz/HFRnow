import Foundation
import Testing
@testable import HFRParsing

/// #1363: HFR serves a profile to a logged-in session only since 2026-11-26 (`R1363a`, 403 without cookies), so the app sends
/// the account's session. Expectations written from reading the logged-in capture `R1363b` (the kit account user1 viewing its
/// own profile), not from the oracle: no legacy export covers a logged-in page.
@Suite("User profile parser, logged-in page")
struct UserProfileLoggedInTests {
    private static let capture = "R1363b-profile-own-user1"

    @Test("R1363b: pseudo, status, avatar, the same sections and fields as a logged-out page")
    func fields() throws {
        let profile = try UserProfileParser.parse(html: Fixture.capture(Self.capture))
        #expect(profile.pseudo == "user1")
        #expect(profile.status == "Membre")
        #expect(profile.avatarURL?.absoluteString == "https://forum-images.hardware.fr/images/mesdiscussions-900001.jpg")
        #expect(profile.sections.map(\.title) == ["Informations générales", "Informations relatives au forum"])
        #expect(profile.sections.map(\.fields.count) == [7, 6])
        #expect(profile.messageCount == 100)
        #expect(profile.joinDate == Date(timeIntervalSince1970: 946_681_200))
        #expect(profile.lastMessageDate == Date(timeIntervalSince1970: 946_681_200))
        let fields = Dictionary(uniqueKeysWithValues: profile.sections.flatMap(\.fields).map { ($0.title, $0.value) })
        #expect(fields["Date de naissance"] == "01/01/2000")
        #expect(fields["Email"] == "Vous n'avez pas accès à cette information")
    }

    @Test("R1363b: six personal smileys, in page order")
    func smileys() throws {
        let profile = try UserProfileParser.parse(html: Fixture.capture(Self.capture))
        #expect(profile.personalSmilies.map(\.code) == ["[:user1]"] + (1...5).map { "[:user1:\($0)]" })
        let paths = ["/images/perso/user1.gif"] + (1...5).map { "/images/perso/\($0)/user1.gif" }
        #expect(profile.personalSmilies.map(\.imageURL.path) == paths)
    }

    @Test("R1363b: the colours row is a link action, and the logged-in « Ajouter … à votre liste de contacts » row is add-contact")
    func actions() throws {
        let profile = try UserProfileParser.parse(html: Fixture.capture(Self.capture))
        #expect(profile.actions.map(\.kind) == [.transaction, .transaction, .link, .privateMessage, .allMessages, .addContact])
        let colours = try #require(profile.actions.first { $0.kind == .link })
        #expect(colours.url.absoluteString == "https://forum.hardware.fr/setperso.php?config=hfr.inc&util=user1")
        let contact = try #require(profile.actions.last)
        #expect(contact.url.absoluteString == "https://forum.hardware.fr/user/contactlist.php?adduser=900001")
        #expect(contact.title == "Ajouter user1 à votre liste de contacts")
    }
}
