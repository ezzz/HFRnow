import HFRModels
import HFRStorage
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

    /// #512: a row menu's page of the topic on screen keeps the selection, so the detail stack only changes identity, which leaves
    /// what a link pushed on top (`SidebarDetailHostedTests`): opening it closes every reader the links had opened.
    @Test func openingARowAtAPageClosesTheReadersLinksOpened() throws {
        let model = NavigationModel(dataSource: FakeDataSource())
        model.selectedSource = .favorites
        let topic = topicSummary(1)
        model.selectedTopic = topic
        let first = try #require(model.reader(for: topic))
        let topicID = TopicID(category: .forum(13), topic: 1)
        first.follow(ReaderTarget(source: .topic(topicID), page: 4))
        let linked = try #require(first.linkedReader)
        linked.follow(ReaderTarget(source: .topic(topicID), page: 5))
        #expect(linked.linkedReader != nil)
        model.open(topic, at: TopicOpening(target: ReaderTarget(source: .topic(topicID), page: 2)))
        #expect(first.linkedReader == nil)
        #expect(linked.linkedReader == nil)
    }

    /// #1089 review finding 1: whatever drops or changes the selection drops the reader with what its links pushed, so the old
    /// root view leaves (its `onDisappear` skips a reader that still covers itself) and the topic reopens fresh.
    @Test(arguments: ["nil", "another", "source"])
    func droppingTheSelectionDropsTheReaderAndItsLinkedReaders(change: String) throws {
        let model = NavigationModel(dataSource: FakeDataSource())
        model.selectedSource = .favorites
        let topic = topicSummary(1)
        model.selectedTopic = topic
        let first = try #require(model.reader(for: topic))
        first.follow(ReaderTarget(source: .topic(TopicID(category: .forum(13), topic: 1)), page: 4))
        switch change {
        case "nil": model.selectedTopic = nil
        case "another": model.selectedTopic = topicSummary(2)
        default: model.selectedSource = .flagged
        }
        #expect(first.linkedReader == nil)
        #expect(model.reader(for: topic) !== first)
    }

    /// The same topic selected again (a list reload hands a new summary of it) keeps its reader and the page a link pushed.
    @Test func reselectingTheSameTopicKeepsTheReader() throws {
        let model = NavigationModel(dataSource: FakeDataSource())
        model.selectedSource = .favorites
        model.selectedTopic = topicSummary(1)
        let first = try #require(model.reader(for: topicSummary(1)))
        first.follow(ReaderTarget(source: .topic(TopicID(category: .forum(13), topic: 1)), page: 4))
        model.selectedTopic = topicSummary(1, title: "Titre mis à jour")
        #expect(model.reader(for: topicSummary(1)) === first)
        #expect(first.linkedReader != nil)
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

    /// #1195: the home page was read logged out, then the member logged in again in place (same session object, so the root
    /// is not rebuilt). The list on screen and the next ones load with the chosen filter, without a pull on Catégories.
    @Test func aReloginInPlaceMakesTheListsLoggedInWithoutAManualRefresh() async {
        let source = FakeDataSource()
        let loggedIn = LoginFlag()
        loggedIn.value = false
        source.forumHandler = {
            ForumListPage(forums: [ForumCategory(categoryID: .forum(13), title: "A", path: "/a")], isLoggedIn: loggedIn.value)
        }
        let filter = TopicFilterModel(settings: InMemorySettingsStore([SettingKey.topicListFlag.key: .int(1)]))
        let model = NavigationModel(dataSource: source, sessionIsLoggedIn: { loggedIn.value }, topicFilter: filter)
        await model.forums.loadIfNeeded()
        let category = TopicSource.forum(.forum(13), title: "A")
        model.selectedSource = category
        let list = model.topicList(for: category)
        await list.loadIfNeeded()
        #expect(!list.offersFilter)
        #expect(source.requests == ["forums", "topics:13:1"])

        loggedIn.value = true
        await model.forums.sessionDidChange()
        await model.reloadShownLists()

        #expect(source.requests == ["forums", "topics:13:1", "forums", "topics:13:1:owntopic=3"])
        #expect(list.offersFilter)
        #expect(await model.isLoggedIn())
    }

    /// The home page read before the change no longer answers, even when its reload fails: the session does (#1195).
    @Test func afterASessionChangeAnOldHomePageNoLongerSaysWhetherTheAccountIsSignedIn() async {
        let source = FakeDataSource()
        source.forumHandler = { ForumListPage(forums: [ForumCategory(categoryID: .forum(1), title: "A", path: "/a")], isLoggedIn: false) }
        let model = NavigationModel(dataSource: source, sessionIsLoggedIn: { true })
        await model.forums.loadIfNeeded()
        #expect(await !model.isLoggedIn())
        source.forumHandler = { () async throws(ListLoadError) -> ForumListPage in throw .offline }
        await model.forums.sessionDidChange()
        #expect(model.forums.loader.value?.isLoggedIn == false) // the list stays on screen
        #expect(await model.isLoggedIn())
        // A page loaded after the change answers again.
        source.forumHandler = { ForumListPage(forums: [], isLoggedIn: false) }
        await model.forums.reload()
        #expect(await !model.isLoggedIn())
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
