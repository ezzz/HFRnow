import Foundation
import HFRModels
import HFRNetwork
import HFRStorage
@testable import SwiftHFR
import Testing

/// A scripted search source: records every call, answers from closures.
final class FakeSearchSource: ForumSearchSource, @unchecked Sendable {
    private let lock = NSLock()
    private var queries: [GlobalSearchQuery] = []
    private var paths: [String] = []
    var searchHandler: @Sendable (GlobalSearchQuery) async throws(ListLoadError) -> TopicListPage = { _ in searchPage(1) }
    var pageHandler: @Sendable (String) async throws(ListLoadError)
        -> TopicListPage = { path in
        switch path {
        case "/first": searchPage(1)
        case "/last": searchPage(3)
        default: searchPage(2)
        }
    }

    var sentQueries: [GlobalSearchQuery] { lock.withLock { queries } }
    var requestedPaths: [String] { lock.withLock { paths } }

    func search(_ query: GlobalSearchQuery) async throws(ListLoadError) -> TopicListPage {
        lock.withLock { queries.append(query) }
        return try await searchHandler(query)
    }

    func page(atPath path: String) async throws(ListLoadError) -> TopicListPage {
        lock.withLock { paths.append(path) }
        return try await pageHandler(path)
    }
}

/// A results page `page` of 3, with its pager paths.
func searchPage(_ page: Int) -> TopicListPage {
    TopicListPage(
        topics: [topicSummary(page * 10)],
        navigation: PageNavigation(
            current: page, firstPath: page > 1 ? "/first" : nil, lastPath: page < 3 ? "/last" : nil,
            nextPath: page < 3 ? "/next\(page)" : nil, previousPath: page > 1 ? "/prev\(page)" : nil
        )
    )
}

@MainActor
struct ForumSearchModelTests {
    private func model(
        _ source: FakeSearchSource = FakeSearchSource(), store: (any SettingsStore)? = nil,
        now: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> ForumSearchModel {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return ForumSearchModel(source: source, store: store, now: { now }, calendar: calendar)
    }

    @Test func aBannedWordIsRefusedWithAWarningAndSendsNothing() async {
        let source = FakeSearchSource()
        let search = model(source)
        search.text = "Mon JailBreak iOS"
        await search.search()
        #expect(search.bannedWord == "jailbreak")
        #expect(source.sentQueries.isEmpty)
        #expect(search.loader.value == nil)
        #expect(!search.hasSearched)
    }

    @Test func aBannedWordInsideAnotherWordIsRefusedAndTheNextSearchClearsTheWarning() async {
        let source = FakeSearchSource()
        let search = model(source)
        search.text = "penguin"
        await search.search()
        #expect(search.bannedWord == "pengu")
        search.text = "pingouin"
        await search.search()
        #expect(search.bannedWord == nil)
        #expect(source.sentQueries.count == 1)
    }

    @Test func accentsReachTheEngineUntouched() async {
        let source = FakeSearchSource()
        let search = model(source)
        search.text = "  Pâtes à l'ail  "
        await search.search()
        #expect(source.sentQueries.map(\.text) == ["Pâtes à l'ail"])
    }

    @Test func blankTextSendsNothing() async {
        let source = FakeSearchSource()
        let search = model(source)
        search.text = " \n "
        #expect(!search.canSubmit)
        await search.search()
        #expect(source.sentQueries.isEmpty)
        #expect(!search.hasSearched)
    }

    @Test func theFormReachesTheQueryWithLegacyDefaults() async {
        let source = FakeSearchSource()
        let search = model(source)
        search.text = "ssd"
        await search.search()
        #expect(source.sentQueries == [GlobalSearchQuery(text: "ssd")])
        search.category = .forum(1)
        search.matchMode = .anyWord
        search.scope = .title
        await search.search()
        #expect(source.sentQueries.last == GlobalSearchQuery(text: "ssd", category: .forum(1), matchMode: .anyWord, scope: .title))
    }

    @Test func thePeriodIsAStartDateRelativeToToday() {
        // 2023-11-14 UTC.
        let search = model()
        #expect(search.dateRange() == .fromBeginning)
        search.period = .oneYear
        #expect(search.dateRange() == .since(day: 14, month: 11, year: 2022))
        search.period = .fiveYears
        #expect(search.dateRange() == .since(day: 14, month: 11, year: 2018))
    }

    @Test func shortWordsOnlyHint() async {
        let source = FakeSearchSource()
        let search = model(source)
        search.text = "ssd nvme"
        #expect(search.hasShortWord)
        search.text = "nvme disque"
        #expect(!search.hasShortWord)
        search.text = "ssd"
        await search.search()
        #expect(source.sentQueries.count == 1)
    }

    @Test func pagingFollowsThePagerPaths() async {
        let source = FakeSearchSource()
        let search = model(source)
        search.text = "ssd"
        await search.search()
        #expect(search.loader.value?.page == 1)
        #expect(search.canGoToNext && !search.canGoToPrevious)
        await search.goToPreviousPage()
        #expect(source.requestedPaths.isEmpty)
        await search.goToNextPage()
        #expect(source.requestedPaths == ["/next1"])
        #expect(search.loader.value?.page == 2)
        await search.goToPreviousPage()
        #expect(source.requestedPaths == ["/next1", "/prev2"])
        await search.goToNextPage()
        await search.goToFirstPage()
        #expect(source.requestedPaths.last == "/first")
        #expect(search.loader.value?.page == 1)
        #expect(!search.canGoToPrevious)
        await search.goToLastPage()
        #expect(source.requestedPaths.last == "/last")
        #expect(search.loader.value?.page == 3)
        #expect(!search.canGoToNext)
    }

    @Test func aFailedNewSearchDropsThePreviousQuerysRowsAndPager() async {
        let source = FakeSearchSource()
        let search = model(source)
        search.text = "ssd"
        await search.search()
        #expect(search.loader.value != nil)
        source.searchHandler = { _ throws(ListLoadError) in throw .offline }
        search.text = "nvme"
        await search.search()
        #expect(search.loader.value == nil)
        #expect(!search.canGoToNext)
        #expect(search.loader.error == .offline)
    }

    @Test func aFailedPageKeepsTheRowsAndRetryAsksForThePageAgain() async {
        let source = FakeSearchSource()
        let search = model(source)
        search.text = "ssd"
        await search.search()
        source.pageHandler = { _ throws(ListLoadError) in throw .timedOut }
        await search.goToNextPage()
        #expect(search.loader.error == .timedOut)
        #expect(search.loader.value?.page == 1)
        source.pageHandler = { _ in searchPage(2) }
        await search.retry()
        #expect(source.requestedPaths == ["/next1", "/next1"])
        #expect(search.loader.value?.page == 2)
        #expect(search.loader.error == nil)
    }

    @Test func noResultKeepsHFRsSentence() async {
        let source = FakeSearchSource()
        source.searchHandler = { _ in TopicListPage(notice: "Aucune réponse n'a été trouvée") }
        let search = model(source)
        search.text = "xyzzy"
        await search.search()
        #expect(search.hasSearched)
        #expect(search.loader.value?.topics.isEmpty == true)
        #expect(search.loader.value?.notice == "Aucune réponse n'a été trouvée")
    }

    @Test func aFailedSearchIsReportedAndRetriedAsAWholeSearch() async {
        let source = FakeSearchSource()
        source.searchHandler = { _ throws(ListLoadError) in throw .offline }
        let search = model(source)
        search.text = "ssd"
        await search.search()
        #expect(search.loader.error == .offline)
        source.searchHandler = { _ in searchPage(1) }
        await search.retry()
        #expect(source.sentQueries.count == 2)
        #expect(search.loader.error == nil)
    }

    @Test func categoriesComeFromTheForumListAndKeepTheChoiceOrFallBackToDiscussions() {
        let search = model()
        func content(_ ids: [Int]) -> ForumListContent {
            let forums = ids.map { ForumCategory(categoryID: .forum($0), title: "Forum \($0)", path: "/p\($0)") }
            return ForumListContent(
                page: ForumListPage(forums: forums, isLoggedIn: true),
                visibility: ForumVisibility(), accountName: "someone"
            )
        }
        search.setCategories(from: content([1, 13, 25]))
        #expect(search.categories.map(\.id) == [.forum(1), .forum(13), .forum(25)])
        search.category = .forum(1)
        search.setCategories(from: content([1, 13]))
        #expect(search.category == .forum(1))
        search.setCategories(from: content([13, 24]))
        #expect(search.category == .forum(13))
        search.setCategories(from: nil)
        #expect(search.categories.isEmpty)
    }

    @Test func aResultOpensAtTheMatchingMessage() {
        var topic = topicSummary(7)
        // The shape of a captured result link (R50b): a `numreponse`, no fragment; HFR picks the page.
        topic.searchHit = SearchHit(
            postPath: "/forum2.php?config=hfr.inc&cat=13&post=7&page=1&p=1&sondage=0&owntopic=0&trash=0&trash_post=0&print=0"
                + "&numreponse=75456630&quote_only=0&new=0&nojs=0",
            snippet: "…"
        )
        let target = ForumSearchModel.target(of: topic)
        #expect(target?.numreponse == 75456630)
        #expect(ForumSearchModel.target(of: topicSummary(7)) != nil)
    }

    @Test func theAppleCategoryIsNotOfferedLoggedOutOrToTheReviewAccount() {
        let search = model()
        let forums = [13, 25].map { ForumCategory(categoryID: .forum($0), title: "Forum \($0)", path: "/p\($0)") }
        let loggedOut = ForumListContent(page: ForumListPage(forums: forums), visibility: ForumVisibility(), accountName: nil)
        search.setCategories(from: loggedOut)
        #expect(search.categories.map(\.id) == [.forum(13)])
        let review = ForumListContent(
            page: ForumListPage(forums: forums, isLoggedIn: true), visibility: ForumVisibility(), accountName: "applereview"
        )
        search.category = .forum(25)
        search.setCategories(from: review)
        #expect(search.categories.map(\.id) == [.forum(13)])
        #expect(search.category == .forum(13))
    }

    @Test func aStoredPrivateMessagesCategoryFallsBackToDiscussionsBeforeSending() async {
        let source = FakeSearchSource()
        let store = InMemorySettingsStore()
        store.set(CategoryID.privateMessages, for: SettingKey.searchCategory)
        let search = model(source, store: store)
        search.text = "ssd"
        await search.search()
        #expect(source.sentQueries.first?.category == .forum(13))
    }

    @Test func theChosenCategoryIsKeptBetweenLaunches() {
        let store = InMemorySettingsStore()
        #expect(model(store: store).category == .forum(13))
        model(store: store).category = .forum(5)
        #expect(model(store: store).category == .forum(5))
    }

    @Test func aNewSearchDropsTheOpenResult() async {
        let search = model()
        search.text = "ssd"
        await search.search()
        search.selected = search.loader.value?.topics.first
        await search.search()
        #expect(search.selected == nil)
    }
}
