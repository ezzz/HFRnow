import Foundation
import HFRModels
import Testing
@testable import HFRNetwork

struct HFREndpointReadTests {
    private static let host = "https://forum.hardware.fr"

    @Test func homeAndBackgroundCheck() throws {
        let home = try HFREndpoint.home()
        #expect(home.url.absoluteString == "\(Self.host)/")
        #expect(home.method == .get)
        #expect(home.timeout == RequestTimeout.standard)
        #expect(home.redirectPolicy == .follow)
        let check = try HFREndpoint.privateMessageCheck()
        #expect(check.url == home.url)
        #expect(check.timeout == RequestTimeout.background)
    }

    @Test(arguments: [
        (CategoryID.forum(13), TopicListFilter.all, 1,
         "/forum1.php?config=hfr.inc&cat=13&page=1&subcat=&owntopic=0"),
        (CategoryID.forum(13), TopicListFilter.flagged, 2,
         "/forum1.php?config=hfr.inc&cat=13&page=2&subcat=&owntopic=1"),
        (CategoryID.forum(1), TopicListFilter.read, 10,
         "/forum1.php?config=hfr.inc&cat=1&page=10&subcat=&owntopic=2"),
        (CategoryID.forum(32), TopicListFilter.favorites, 1,
         "/forum1.php?config=hfr.inc&cat=32&page=1&subcat=&owntopic=3")
    ])
    func topicList(category: CategoryID, filter: TopicListFilter, page: Int, expected: String) throws {
        let request = try HFREndpoint.topicList(category: category, filter: filter, page: page)
        #expect(request.url.absoluteString == Self.host + expected)
        #expect(request.method == .get)
        #expect(request.body == nil)
    }

    @Test func topicListDefaultsToFirstPageOfAllTopics() throws {
        let request = try HFREndpoint.topicList(category: .forum(25))
        #expect(request.url.absoluteString == "\(Self.host)/forum1.php?config=hfr.inc&cat=25&page=1&subcat=&owntopic=0")
    }

    @Test func topicListRefusesPrivateCategoryAndBadPages() {
        #expect(throws: NetworkError.self) { try HFREndpoint.topicList(category: .privateMessages) }
        #expect(throws: NetworkError.self) { try HFREndpoint.topicList(category: .forum(1), page: 0) }
        #expect(throws: NetworkError.self) { try HFREndpoint.topicList(category: .forum(1), page: -3) }
    }

    @Test(arguments: [
        (TopicListFilter.favorites, "/forum1f.php?owntopic=3"),
        (TopicListFilter.flagged, "/forum1f.php?owntopic=1")
    ])
    func favorites(filter: TopicListFilter, expected: String) throws {
        #expect(try HFREndpoint.favorites(filter: filter).url.absoluteString == Self.host + expected)
    }

    @Test func favoritesDefaultsToFavouritesAndRefusesOtherFilters() throws {
        #expect(try HFREndpoint.favorites().url.absoluteString == "\(Self.host)/forum1f.php?owntopic=3")
        #expect(throws: NetworkError.self) { try HFREndpoint.favorites(filter: .all) }
        #expect(throws: NetworkError.self) { try HFREndpoint.favorites(filter: .read) }
    }

    @Test func privateMessages() throws {
        #expect(try HFREndpoint.privateMessages().url.absoluteString == "\(Self.host)/forum1.php?config=hfr.inc&cat=prive&page=1")
        #expect(try HFREndpoint.privateMessages(page: 3).url.absoluteString == "\(Self.host)/forum1.php?config=hfr.inc&cat=prive&page=3")
        #expect(throws: NetworkError.self) { try HFREndpoint.privateMessages(page: 0) }
    }

    @Test(arguments: [
        (EditProfilePage.hashAndAvatar, "/user/editprofil.php?config=hfr.inc&page=5"),
        (EditProfilePage.cookieRefresh, "/user/editprofil.php?config=hfr.inc&page=1")
    ])
    func editProfile(page: EditProfilePage, expected: String) throws {
        #expect(try HFREndpoint.editProfile(page: page).url.absoluteString == Self.host + expected)
    }

    @Test func publicProfile() throws {
        #expect(try HFREndpoint.publicProfile(memberID: 12345).url.absoluteString == "\(Self.host)/hfr/profil-12345.htm")
        #expect(throws: NetworkError.self) { try HFREndpoint.publicProfile(memberID: -1) }
    }

    @Test(arguments: [
        ("/forum2.php?config=hfr.inc&cat=13&post=42&page=2", "\(host)/forum2.php?config=hfr.inc&cat=13&post=42&page=2"),
        ("/hfr/Discussions/x-sujet_42_2.htm", "\(host)/hfr/Discussions/x-sujet_42_2.htm"),
        ("//forum.hardware.fr/hfr/ia/liste_sujet-1.htm", "https://forum.hardware.fr/hfr/ia/liste_sujet-1.htm"),
        ("https://forum.hardware.fr/hfr/ia/liste_sujet-1.htm", "https://forum.hardware.fr/hfr/ia/liste_sujet-1.htm"),
        ("  /forum1f.php?owntopic=3 ", "\(host)/forum1f.php?owntopic=3")
    ])
    func absoluteURLAcceptsForumLinks(href: String, expected: String) {
        #expect(HFREndpoint.absoluteURL(href: href)?.absoluteString == expected)
    }

    @Test(arguments: ["", "   ", "https://example.com/forum2.php", "ftp://forum.hardware.fr/", "javascript:alert(1)",
                      "https://forum.hardware.fr.evil.example/"])
    func absoluteURLRefusesOtherHosts(href: String) {
        #expect(HFREndpoint.absoluteURL(href: href) == nil)
    }
}
