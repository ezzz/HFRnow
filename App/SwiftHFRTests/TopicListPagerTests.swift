import HFRModels
@testable import SwiftHFR
import Testing

/// The « page x / y » pager of a category's topic list (#980), with the same rules as the MP list's (#968).
@MainActor
struct TopicListPagerTests {
    private func model(_ source: FakeDataSource) -> TopicListModel {
        TopicListModel(source: .forum(.forum(13), title: "Discussions"), dataSource: source, isLoggedIn: { true })
    }

    /// A forum list of `last` pages whose pager is exact, so « Dernière page » is offered.
    private func exactPages(_ source: FakeDataSource, last: Int) {
        source.topicHandler = { _, page in
            TopicListPage(
                topics: [topicSummary(page)],
                navigation: PageNavigation(
                    current: page, last: last, isExact: true, nextPath: page < last ? "/next" : nil, previousPath: page > 1 ? "/prev" : nil
                )
            )
        }
    }

    @Test func pageCountIsTheLastPageHFRLinksToAndAtLeastTheCurrentPage() async {
        let source = FakeDataSource()
        let model = model(source)
        #expect(model.pageCount == 1)
        await model.loadIfNeeded()
        #expect(model.pageCount == 5)
        #expect(!model.pageCountIsExact, "the fake pager is a window: only a lower bound")
        source.topicHandler = { _, page in
            TopicListPage(topics: [topicSummary(page)], navigation: PageNavigation(current: 9, last: 3, nextPath: "/next"))
        }
        await model.goToNextPage()
        #expect(model.pageCount == 10, "a next page exists: at least one more than the page on screen")
    }

    @Test func theLastPageIsExactWhenThereIsNoNextPage() async {
        let source = FakeDataSource()
        let model = model(source)
        await model.loadIfNeeded()
        await model.goToPage(5)
        #expect(model.currentPage == 5)
        #expect(model.pageCountIsExact)
        #expect(model.pageCount == 5)
    }

    @Test func menuStepsReachFirstPreviousNextAndLast() async {
        let source = FakeDataSource()
        exactPages(source, last: 7)
        let model = model(source)
        await model.loadIfNeeded()
        await model.perform(.next)
        await model.perform(.next)
        await model.perform(.previous)
        await model.perform(.last)
        await model.perform(.first)
        #expect(source.requests == ["topics:13:1", "topics:13:2", "topics:13:3", "topics:13:2", "topics:13:7", "topics:13:1"])
    }

    @Test func aTypedPageIsExactlyThatPage() async {
        let source = FakeDataSource()
        exactPages(source, last: 7)
        let model = model(source)
        await model.loadIfNeeded()
        await model.perform(.page(4))
        #expect(model.currentPage == 4)
        await model.perform(.page(99))
        #expect(model.currentPage == 7, "clamped to the real last page")
        await model.perform(.page(0))
        #expect(model.currentPage == 1)
    }

    @Test func aTypedPagePastAWindowIsAskedAsTyped() async {
        let source = FakeDataSource()
        let model = model(source)
        await model.loadIfNeeded()
        await model.perform(.page(12))
        #expect(source.requests == ["topics:13:1", "topics:13:12"], "the last page is only a lower bound: no clamp")
    }

    @Test func lastIsNotOfferedWhileTheLastPageIsALowerBound() async {
        let source = FakeDataSource()
        let model = model(source)
        await model.loadIfNeeded()
        #expect(model.canGoToNext)
        #expect(!model.canGoToLast)
        await model.perform(.last)
        #expect(source.requests == ["topics:13:1"])
    }

    @Test func boundsDisableTheStepsAndLastIsOfferedOnAnExactPager() async {
        let source = FakeDataSource()
        exactPages(source, last: 3)
        let model = model(source)
        await model.loadIfNeeded()
        #expect(!model.canGoToPrevious)
        #expect(model.canGoToNext && model.canGoToLast)
        await model.perform(.last)
        #expect(model.canGoToPrevious)
        #expect(!model.canGoToNext && !model.canGoToLast)
        await model.perform(.next)
        #expect(source.requests == ["topics:13:1", "topics:13:3"], "next past the end asks for nothing")
    }

    /// Flags and favourites are one page: the count stays 1 and a typed page sends nothing more. (`goToPage`'s `isPaged` guard is not
    /// observable here: a one-page count clamps the target to the page on screen.)
    @Test func flagsAndFavouritesStayOnOnePage() async {
        let source = FakeDataSource()
        let model = TopicListModel(source: .flagged, dataSource: source, isLoggedIn: { true })
        await model.loadIfNeeded()
        await model.perform(.page(3))
        #expect(!model.canGoToNext && !model.canGoToLast)
        #expect(model.pageCount == 1 && model.currentPage == 1)
        #expect(source.requests == ["favorites:1"], "a typed page asks for nothing more")
    }
}
