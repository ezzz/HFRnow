import HFRModels
import Synchronization
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

    @Test func theRefreshButtonIsDisabledOnlyWhileALoadRuns() async {
        let source = FakeDataSource()
        let model = forumModel(source)
        #expect(model.canRefresh)
        let during = Mutex<[Bool]>([])
        source.topicHandler = { _, page in
            let enabled = await model.canRefresh
            during.withLock { $0.append(enabled) }
            return topicPage(page: page)
        }
        await model.loadIfNeeded()
        await model.refresh()
        #expect(during.withLock { $0 } == [false, false])
        #expect(model.canRefresh)
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

    @Test func aSubforumPagesThroughItsOwnLinkAndRefreshesTheCurrentPage() async {
        let source = FakeDataSource()
        let path = "/hfr/Hardware/minipc/liste_sujet-1.htm"
        let model = TopicListModel(source: .subforum(path: path, title: "Mini PC"), dataSource: source)
        await model.loadIfNeeded()
        await model.goToNextPage()
        await model.refresh()
        #expect(source.requests == ["path:\(path):1", "path:\(path):2", "path:\(path):2"])
        #expect(model.canGoToPrevious)
    }

    @Test func flagsAndFavouritesRefreshWhenTheyReappearKeepingRows() async {
        let source = FakeDataSource()
        let model = TopicListModel(source: .flagged, dataSource: source)
        await model.onAppear()
        await model.onAppear()
        #expect(source.requests == ["favorites:1", "favorites:1"])
    }

    @Test func aForumPageIsNotReloadedWhenItReappears() async {
        let source = FakeDataSource()
        let model = forumModel(source)
        await model.onAppear()
        await model.onAppear()
        #expect(source.requests == ["topics:13:1"])
    }
}

/// The "Nouveau sujet" entry of a forum list (LOT-089).
@MainActor
struct TopicListNewTopicTests {
    private func listPage(path: String?, category: CategoryID?) -> TopicListPage {
        var page = topicPage(page: 1)
        page.newTopicPath = path
        page.categoryID = category
        return page
    }

    private func model(_ page: TopicListPage, source: FakeDataSource = FakeDataSource()) -> TopicListModel {
        source.topicHandler = { _, number in
            var served = page
            served.navigation = topicPage(page: number).navigation
            return served
        }
        return TopicListModel(source: .forum(.forum(13), title: "Discussions"), dataSource: source, isLoggedIn: { true })
    }

    @Test func theListsLinkAndCategoryGiveTheTargetOnlyOnceLoaded() async {
        let list = model(listPage(path: "/hfr/Discussions/nouveau_sujet.htm", category: .forum(13)))
        #expect(list.newTopicTarget == nil)
        await list.loadIfNeeded()
        #expect(list.newTopicTarget?.draftContext == .newTopic(forum: .forum(13)))
    }

    @Test func noLinkOrNoCategoryOffersNothing() async {
        let withoutLink = model(listPage(path: nil, category: .forum(13)))
        await withoutLink.loadIfNeeded()
        #expect(withoutLink.newTopicTarget == nil)
        let withoutCategory = model(listPage(path: "/hfr/Discussions/nouveau_sujet.htm", category: nil))
        await withoutCategory.loadIfNeeded()
        #expect(withoutCategory.newTopicTarget == nil)
    }

    @Test func favouritesOfferNoNewTopic() async {
        let list = TopicListModel(source: .favorites, dataSource: FakeDataSource(), isLoggedIn: { true })
        await list.loadIfNeeded()
        #expect(list.newTopicTarget == nil)
    }

    @Test func aConfirmedTopicReloadsPageOneAndShowsHFRsSentence() async {
        let source = FakeDataSource()
        let list = model(listPage(path: "/hfr/Discussions/nouveau_sujet.htm", category: .forum(13)), source: source)
        await list.loadIfNeeded()
        await list.goToNextPage()
        await list.newTopicDidClose(.sent(newTopicConfirmed))
        #expect(source.requests == ["topics:13:1", "topics:13:2", "topics:13:1"])
        #expect(list.currentPage == 1)
        #expect(list.sentConfirmation == "Votre message a été posté avec succès !")
        list.clearSentConfirmation()
        #expect(list.sentConfirmation == nil)
    }

    @Test func anUnconfirmedTopicReloadsWithoutASentence() async {
        let source = FakeDataSource()
        let list = model(listPage(path: "/hfr/Discussions/nouveau_sujet.htm", category: .forum(13)), source: source)
        await list.loadIfNeeded()
        await list.goToNextPage()
        await list.newTopicDidClose(.checkTopic)
        #expect(source.requests == ["topics:13:1", "topics:13:2", "topics:13:1"])
        #expect(list.sentConfirmation == nil)
    }

    @Test func closingWithOrWithoutTheDraftChangesNothing() async {
        let source = FakeDataSource()
        let list = model(listPage(path: "/hfr/Discussions/nouveau_sujet.htm", category: .forum(13)), source: source)
        await list.loadIfNeeded()
        for reason in [ReplyComposerModel.CloseReason.keptDraft, .discardedDraft, .closedWithoutSaving] {
            await list.newTopicDidClose(reason)
        }
        #expect(source.requests.count == 1)
        #expect(list.sentConfirmation == nil)
    }
}
