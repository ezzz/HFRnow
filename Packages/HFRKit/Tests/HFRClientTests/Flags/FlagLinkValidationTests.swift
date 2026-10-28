import Foundation
import HFRModels
import HFRNetwork
import Testing
@testable import HFRClient

/// A flag link is followed with the account's cookies: anything but the write's own forum link is refused unsent.
@Suite("Flag link validation")
struct FlagLinkValidationTests {
    static let query = "config=hfr.inc&cat=13&post=28563&numreponse=2666649&page=1&ref=1&p=1&sondage=0&owntopic=0&subcat=433"

    @Test(
        "Links that are not this write's are refused before any request",
        arguments: [
            "http://forum.hardware.fr/user/addflag.php?\(query)",
            "https://forum.hardware.fr:8443/user/addflag.php?\(query)",
            "https://evil.example/user/addflag.php?\(query)",
            "https://forum.hardware.fr.evil.example/user/addflag.php?\(query)",
            "https://other.hardware.fr/user/addflag.php?\(query)",
            "https://user@forum.hardware.fr/user/addflag.php?\(query)",
            "https://forum.hardware.fr/user/delflag.php?\(query)",
            "https://forum.hardware.fr/user/addflag.php.evil?\(query)",
            "https://forum.hardware.fr/user/addflag.php/x?\(query)",
            "https://forum.hardware.fr/USER/addflag.php?\(query)",
            "https://forum.hardware.fr/x/user/addflag.php?\(query)",
            "https://forum.hardware.fr/redirect.php?u=/user/addflag.php&\(query)",
            "https://forum.hardware.fr/user/addflag.php",
            "https://forum.hardware.fr/user/addflag.php?config=hfr.inc&post=28563",
            "https://forum.hardware.fr/user/addflag.php?config=hfr.inc&cat=13",
            "https://forum.hardware.fr/user/addflag.php?cat=13&post=28563",
            "https://forum.hardware.fr/user/addflag.php?config=other&cat=13&post=28563",
            "https://forum.hardware.fr/user/addflag.php?config=hfr.inc&cat=prive&post=28563",
            "https://forum.hardware.fr/user/addflag.php?config=hfr.inc&cat=0&post=28563",
            "https://forum.hardware.fr/user/addflag.php?config=hfr.inc&cat=-1&post=28563",
            "https://forum.hardware.fr/user/addflag.php?config=hfr.inc&cat=13&post=0",
            "https://forum.hardware.fr/user/addflag.php?config=hfr.inc&cat=13&post=-5",
            "https://forum.hardware.fr/user/addflag.php?config=hfr.inc&cat=13&post=%2B5",
            "https://forum.hardware.fr/user/addflag.php?config=hfr.inc&cat=13&post=abc",
            "https://forum.hardware.fr/user/addflag.php?config=hfr.inc&cat=13&post=1&post=2",
            "https://forum.hardware.fr/user/addflag.php?config=hfr.inc&cat=13&cat=14&post=1",
            "https://forum.hardware.fr/user/addflag.php?config=hfr.inc&config=hfr.inc&cat=13&post=1",
            "https://forum.hardware.fr/user/addflag.php?xconfig=hfr.inc&xcat=13&xpost=1"
        ]
    )
    func refused(raw: String) async throws {
        let link = try FlagCapture.url(raw)
        let session = ScriptedFlagSession([try FlagCapture.page("P03a")])
        await #expect(throws: TopicFlagError.invalidLink) {
            try await TopicFlagFlow().follow(.addFavorite, link: link, through: session)
        }
        #expect(await session.requests.isEmpty)
    }

    @Test("A delflag link is refused for addflag and an addflag link for delflag")
    func pathsAreNotInterchangeable() throws {
        let add = try FlagCapture.requestURL("P03a")
        let remove = try FlagCapture.requestURL("P03d")
        #expect(FlagLink(add, path: "/user/delflag.php") == nil)
        #expect(FlagLink(remove, path: "/user/addflag.php") == nil)
        #expect(FlagLink(add, path: "/user/addflag.php") != nil)
        #expect(FlagLink(remove, path: "/user/delflag.php") != nil)
    }

    @Test("The list removal has no link to follow")
    func listRemovalIsNotALinkWrite() async throws {
        let session = ScriptedFlagSession([try FlagCapture.page("P03d")])
        await #expect(throws: TopicFlagError.invalidLink) {
            try await TopicFlagFlow().follow(.removeFavoriteFromList, link: try FlagCapture.requestURL("P03d"), through: session)
        }
        #expect(await session.requests.isEmpty)
    }

    @Test("The public entry points check the link and the topic before using the account's session")
    func publicEntryPointsValidate() async throws {
        let session = HFRSession()
        let foreign = try FlagCapture.url("https://evil.example/user/addflag.php?\(Self.query)")
        await #expect(throws: TopicFlagError.invalidLink) { try await TopicFlagFlow().addFavorite(link: foreign, in: session) }
        await #expect(throws: TopicFlagError.invalidLink) { try await TopicFlagFlow().removeFlag(link: foreign, in: session) }
        let message = TopicID(category: .privateMessages, topic: 1)
        await #expect(throws: TopicFlagError.invalidTopic) { try await TopicFlagFlow().removeFavoriteFromList(message, in: session) }
        await #expect(throws: TopicFlagError.invalidTopic) { try await TopicFlagFlow().markRead(message, page: 1, in: session) }
    }
}
