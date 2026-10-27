import HFRModels
@testable import SwiftHFR
import Testing

@MainActor
struct TopicListModelTests {
    private func forumModel(_ source: FakeDataSource, loggedIn: Bool = true) -> TopicListModel {
        TopicListModel(source: .forum(.forum(13), title: "Discussions"), dataSource: source, isLoggedIn: { loggedIn })
    }

    @Test func firstLoadAsksForPageOne() async {
        let source = FakeDataSource()
        let model = forumModel(source)
        await model.loadIfNeeded()
        await model.loadIfNeeded()
        #expect(source.requests == ["topics:13:1"])
        #expect(model.currentPage == 1)
        #expect(model.canGoToNext)
        #expect(!model.canGoToPrevious)
    }

    @Test func refreshReloadsTheCurrentPageNotPageOne() async {
        let source = FakeDataSource()
        let model = forumModel(source)
        await model.loadIfNeeded()
        await model.goToNextPage()
        await model.goToNextPage()
        await model.refresh()
        #expect(source.requests == ["topics:13:1", "topics:13:2", "topics:13:3", "topics:13:3"])
        #expect(model.currentPage == 3)
    }

    @Test func refreshKeepsTheRowsWhenItFails() async {
        let source = FakeDataSource()
        let model = forumModel(source)
        await model.goToNextPage() // no content yet: ignored
        await model.loadIfNeeded()
        await model.goToNextPage()
        source.topicHandler = { (_, _) async throws(ListLoadError) -> TopicListPage in throw .timedOut }
        await model.refresh()
        #expect(model.loader.value?.groups.first?.topics.map(\.title) == ["Topic 20"])
        #expect(model.loader.error == .timedOut)
        #expect(model.currentPage == 2)
    }

    @Test func aFailedPageChangeKeepsThePageOnScreenAndRetryAsksForTheTarget() async {
        let source = FakeDataSource()
        let model = forumModel(source)
        await model.loadIfNeeded()
        source.topicHandler = { (_, _) async throws(ListLoadError) -> TopicListPage in throw .offline }
        await model.goToNextPage()
        #expect(model.currentPage == 1)
        #expect(model.requestedPage == 2)
        source.topicHandler = { _, page in topicPage(page: page) }
        await model.retry()
        #expect(model.currentPage == 2)
        #expect(model.loader.error == nil)
    }

    @Test func thePagerNeverClaimsATotal() async {
        let source = FakeDataSource()
        let model = forumModel(source)
        await model.loadIfNeeded()
        for _ in 0..<4 { await model.goToNextPage() }
        #expect(model.currentPage == 5)
        #expect(!model.canGoToNext)
        await model.goToFirstPage()
        #expect(model.currentPage == 1)
    }

    @Test func flagsLoadTheFlaggedFilterAndAreNotPaged() async {
        let source = FakeDataSource()
        let model = TopicListModel(source: .flagged, dataSource: source)
        await model.loadIfNeeded()
        await model.goToNextPage()
        #expect(source.requests == ["favorites:1"])
        #expect(!model.canGoToNext)
    }

    @Test func favouritesKeepTheirCategorySections() async {
        let source = FakeDataSource()
        source.favoritesHandler = { _ in
            FavoritesPage(sections: [
                FavoriteSection(forum: ForumLink(title: "Hardware", path: "/h"), categoryID: .forum(1), topics: [topicSummary(1)]),
                FavoriteSection(forum: ForumLink(title: "Discussions", path: "/d"), categoryID: .forum(13), topics: [topicSummary(2)])
            ])
        }
        let model = TopicListModel(source: .favorites, dataSource: source)
        await model.loadIfNeeded()
        #expect(model.loader.value?.groups.map(\.title) == ["Hardware", "Discussions"])
        #expect(model.loader.value?.emptyReason == nil)
    }

    @Test func aMessageInsteadOfAListIsAWallWhenLoggedOutAndANoticeWhenLoggedIn() async {
        let source = FakeDataSource()
        source.favoritesHandler = { _ in FavoritesPage(notice: "Aucun sujet que vous avez lu n'est connu") }
        let loggedOut = TopicListModel(source: .flagged, dataSource: source, isLoggedIn: { false })
        await loggedOut.loadIfNeeded()
        #expect(loggedOut.loader.value?.emptyReason == .signInRequired("Aucun sujet que vous avez lu n'est connu"))
        let loggedIn = TopicListModel(source: .flagged, dataSource: source, isLoggedIn: { true })
        await loggedIn.loadIfNeeded()
        #expect(loggedIn.loader.value?.emptyReason == .notice("Aucun sujet que vous avez lu n'est connu"))
    }

    @Test func anEmptyListWithoutMessageIsSimplyEmpty() async {
        let source = FakeDataSource()
        let model = TopicListModel(source: .favorites, dataSource: source)
        await model.loadIfNeeded()
        #expect(model.loader.value?.emptyReason == .nothing)
    }
}
