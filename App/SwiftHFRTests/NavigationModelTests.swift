import HFRModels
@testable import SwiftHFR
import Testing

@MainActor
struct NavigationModelTests {
    @Test func changingTheSourceClearsTheTopicSelection() {
        let model = NavigationModel(dataSource: FakeDataSource())
        model.selectedSource = .favorites
        model.selectedTopic = topicSummary(1)
        model.selectedSource = .flagged
        #expect(model.selectedTopic == nil)
    }

    @Test func reselectingTheSameSourceKeepsTheTopic() {
        let model = NavigationModel(dataSource: FakeDataSource())
        model.selectedSource = .favorites
        model.selectedTopic = topicSummary(1)
        model.selectedSource = .favorites
        #expect(model.selectedTopic != nil)
    }

    @Test func eachSourceKeepsItsOwnModelSoGoingBackKeepsThePage() async {
        let model = NavigationModel(dataSource: FakeDataSource())
        let forum = TopicSource.forum(.forum(13), title: "Discussions")
        let first = model.topicList(for: forum)
        await first.loadIfNeeded()
        await first.goToNextPage()
        #expect(model.topicList(for: forum) === first)
        #expect(model.topicList(for: forum).currentPage == 2)
        #expect(model.topicList(for: .favorites) !== first)
    }

    @Test func loggedInStateComesFromTheForumListOnceLoaded() async {
        let source = FakeDataSource()
        source.forumHandler = { ForumListPage(forums: [ForumCategory(categoryID: .forum(1), title: "A", path: "/a")], isLoggedIn: true) }
        let model = NavigationModel(dataSource: source)
        #expect(await !model.isLoggedIn())
        await model.forums.loadIfNeeded()
        #expect(await model.isLoggedIn())
    }

    @Test func beforeTheHomePageLoadsTheSessionDecidesSoANoticeIsNotALoginWall() async {
        let source = FakeDataSource()
        source.favoritesHandler = { _ in FavoritesPage(notice: "Aucun sujet") }
        let model = NavigationModel(dataSource: source, sessionIsLoggedIn: { true })
        let flags = model.topicList(for: .flagged)
        await flags.loadIfNeeded()
        #expect(flags.loader.value?.emptyReason == .notice("Aucun sujet"))
    }
}
