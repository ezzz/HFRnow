import Testing
@testable import HFRModels

@Suite struct ForumModelsTests {
    private let hardware = ForumCategory(
        categoryID: .forum(1),
        title: "Hardware",
        path: "/hfr/Hardware/liste_sujet-1.htm",
        subforums: [ForumLink(title: "Benchs", path: "/hfr/Hardware/Benchs/liste_sujet-1.htm")]
    )

    @Test func forumCategoryIdentityIsItsPathAndFollowsMutation() {
        var forum = hardware
        #expect(forum.id == "/hfr/Hardware/liste_sujet-1.htm")
        forum.path = "/hfr/apple/liste_sujet-1.htm"
        #expect(forum.id == "/hfr/apple/liste_sujet-1.htm")
    }

    @Test func forumCategoryRoundTripsWithAndWithoutCategoryID() throws {
        #expect(try roundTrip(hardware) == hardware)
        let withoutID = ForumCategory(title: "ia", path: "/hfr/ia/liste_sujet-1.htm")
        let decoded = try roundTrip(withoutID)
        #expect(decoded == withoutID)
        #expect(decoded.categoryID == nil)
        #expect(decoded.subforums.isEmpty)
    }

    @Test func forumListPageEqualityCoversEveryField() {
        let base = ForumListPage(forums: [hardware], isLoggedIn: true, unreadPrivateMessages: 2, hashCheck: "token")
        var other = base
        #expect(base == other)
        other.unreadPrivateMessages = 3
        #expect(base != other)
        other = base
        other.hashCheck = nil
        #expect(base != other)
    }

    @Test func listPageFailureComparesCaseAndPayload() {
        #expect(ListPageFailure.maintenance("a") == .maintenance("a"))
        #expect(ListPageFailure.maintenance("a") != .maintenance("b"))
        #expect(ListPageFailure.maintenance("a") != .notAuthenticated("a"))
    }

    @Test func listPageFailureIsAnError() {
        let error: any Error = ListPageFailure.malformed("no table")
        #expect(error as? ListPageFailure == .malformed("no table"))
    }

    @Test func forumListPageNeverRevealsTheToken() {
        let page = ForumListPage(forums: [hardware], isLoggedIn: true, hashCheck: "TOKEN-SECRET")
        var dumped = ""
        dump(page, to: &dumped)
        for output in [page.description, page.debugDescription, "\(page)", String(reflecting: page), dumped] {
            #expect(!output.contains("TOKEN-SECRET"))
        }
        #expect(page.description.contains("<redacted>"))
        #expect(ForumListPage(forums: []).description.contains("hashCheck: nil"))
    }
}
