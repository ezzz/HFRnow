import Testing
@testable import HFRModels

@Suite struct ListPagesTests {
    @Test func paginationDefaultsDescribeASinglePage() {
        let navigation = PageNavigation()
        #expect(navigation.current == 1)
        #expect(navigation.first == 1)
        #expect(navigation.last == 1)
        #expect(navigation.nextPath == nil)
        #expect(navigation.previousPath == nil)
    }

    @Test func topicListPageRoundTrips() throws {
        let page = TopicListPage(
            topics: [TopicSummary(topicID: TopicID(category: .forum(13), topic: 1), title: "a", path: "/a")],
            navigation: PageNavigation(current: 2, first: 1, last: 9, nextPath: "/p3", previousPath: "/p1"),
            tabs: TopicListTabs(all: "/all", favorites: "/fav", flagBlue: "/blue", flagRed: "/red"),
            categoryID: .forum(13),
            newTopicPath: "/new",
            unreadPrivateMessages: 4
        )
        #expect(try roundTrip(page) == page)
    }

    @Test func noticePageKeepsTheServerMessageAndRoundTrips() throws {
        let page = TopicListPage(notice: "Aucun favori n'est repertorié")
        #expect(page.topics.isEmpty)
        #expect(page.notice == "Aucun favori n'est repertorié")
        #expect(try roundTrip(page) == page)
        #expect(TopicListPage().notice == nil)
    }

    @Test func emptyTopicListPageIsAValueNotAnError() throws {
        let page = TopicListPage()
        #expect(page.topics.isEmpty)
        #expect(try roundTrip(page) == page)
    }

    @Test func favoriteSectionIdentityPrefersCategoryID() {
        let header = ForumLink(title: "Discussions", path: "/forum1.php?cat=13")
        #expect(FavoriteSection(forum: header, categoryID: .forum(13)).id == "cat:13")
        #expect(FavoriteSection(forum: header, categoryID: .privateMessages).id == "cat:prive")
    }

    @Test func favoriteSectionIdentityFallsBackToTheForumPath() {
        let section = FavoriteSection(forum: ForumLink(title: "X", path: "/hfr/X/"))
        #expect(section.id == "path:/hfr/X/")
    }

    @Test func favoriteSectionsOfDifferentCategoriesHaveDifferentIdentities() {
        let header = ForumLink(title: "Same", path: "/same")
        #expect(FavoriteSection(forum: header, categoryID: .forum(1)).id != FavoriteSection(forum: header, categoryID: .forum(2)).id)
    }

    @Test func favoriteSectionRoundTrips() throws {
        let section = FavoriteSection(
            forum: ForumLink(title: "Discussions", path: "/p"),
            categoryID: .forum(13),
            topics: [TopicSummary(topicID: TopicID(category: .forum(13), topic: 9), title: "t", path: "/t")]
        )
        let decoded = try roundTrip(section)
        #expect(decoded == section)
        #expect(decoded.id == section.id)
    }
}
