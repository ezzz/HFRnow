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

    @Test func changingTheSourceDropsTheReaderSoTheTopicReopensFresh() {
        let model = NavigationModel(dataSource: FakeDataSource())
        model.selectedSource = .favorites
        let topic = topicSummary(1)
        let first = model.reader(for: topic)
        #expect(first != nil)
        #expect(model.reader(for: topic) === first)
        model.selectedSource = .flagged
        #expect(model.reader(for: topic) !== first)
    }

    /// A row menu's page (LOT-125) opens a new reader at that page, even for the topic on screen; a plain selection then keeps it.
    @Test func openingARowAtAPageBuildsANewReaderThere() throws {
        let model = NavigationModel(dataSource: FakeDataSource())
        model.selectedSource = .favorites
        let topic = topicSummary(1)
        model.selectedTopic = topic
        let first = try #require(model.reader(for: topic))
        let generation = model.readerGeneration
        let page = TopicOpening(target: ReaderTarget(source: .topic(TopicID(category: .forum(13), topic: 1)), page: 7))
        model.open(topic, at: page)
        let opened = try #require(model.reader(for: topic))
        #expect(opened !== first)
        #expect(opened.requested == page.target)
        #expect(model.readerGeneration == generation + 1)
        #expect(model.selectedTopic == topic)
        #expect(model.reader(for: topic) === opened)
    }

    @Test func aPageAskedForOneTopicIsNotUsedForAnother() throws {
        let model = NavigationModel(dataSource: FakeDataSource())
        model.selectedSource = .favorites
        let asked = topicSummary(1)
        model.open(asked, at: TopicOpening(target: ReaderTarget(source: .topic(TopicID(category: .forum(13), topic: 1)), page: 7)))
        let other = topicSummary(2)
        #expect(try #require(model.reader(for: other)).requested == ReaderTarget(opening: other))
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
