import HFRModels
import HFRStorage
@testable import SwiftHFR
import Testing

/// The regular-width iPad's detail column as `RootModel` drives it: which reader it shows, and what a new one drops.
@MainActor
struct RootModelDetailColumnTests {
    /// A root over a fake source, opened on `initial`.
    private func model(initial: SidebarDestination) -> RootModel {
        let source = FakeDataSource()
        let forums = ForumListModel(dataSource: source)
        return RootModel(
            forums: forums,
            categories: NavigationModel(dataSource: source, forums: forums, startupSource: RootModel.categoriesStartupSource),
            favorites: NavigationModel(dataSource: source, forums: forums, startupSource: TopicSource(mode: .flagsAndFavorites)),
            messages: MessageListModel(source: FakePrivateMessages()),
            store: InMemorySettingsStore(), initial: initial
        )
    }

    // Regular-width iPad: a Favoris section title switches to Catégories, as legacy (`MainWindow.swift:2221-2232` @ 87fe0d1c), instead
    // of pushing into the detail column.
    @Test func aFavorisSectionTitleSwitchesTheContentColumnToCategoriesOnFavoris() {
        let source = FakeDataSource()
        let filter = TopicFilterModel(settings: InMemorySettingsStore())
        let forums = ForumListModel(dataSource: source)
        let root = RootModel(
            forums: forums,
            categories: NavigationModel(
                dataSource: source, forums: forums, startupSource: RootModel.categoriesStartupSource, topicFilter: filter
            ),
            favorites: NavigationModel(dataSource: source, forums: forums, startupSource: TopicSource(mode: .flagsAndFavorites)),
            messages: MessageListModel(source: FakePrivateMessages()),
            store: InMemorySettingsStore(), initial: .tab(.favorites)
        )
        root.categories.selectedTopic = TopicSummary(
            topicID: TopicID(category: .forum(13), topic: 1), title: "Ancien", path: "/t1", starterOrInterlocutors: "membre",
            readState: .read
        )
        let category = TopicSource.forum(.forum(13), title: "Discussions")
        root.showCategoryFromFavorites(category)
        #expect(root.categories.selectedTopic == nil)
        #expect(root.selectedDestination == .tab(.categories))
        #expect(root.categories.selectedSource == category)
        #expect(filter.flag == .favorites)
    }

    // #1089 review finding 1: a Favoris section title naming the category already open drops the topic but kept its reader, so
    // tapping the same row again showed the page a link had pushed over it.
    @Test func aFavorisSectionTitleOnTheOpenCategoryDropsTheReaderAndWhatItsLinksPushed() throws {
        let source = FakeDataSource()
        let forums = ForumListModel(dataSource: source)
        let root = RootModel(
            forums: forums,
            categories: NavigationModel(dataSource: source, forums: forums, startupSource: RootModel.categoriesStartupSource),
            favorites: NavigationModel(dataSource: source, forums: forums, startupSource: TopicSource(mode: .flagsAndFavorites)),
            messages: MessageListModel(source: FakePrivateMessages()),
            store: InMemorySettingsStore(), initial: .tab(.categories)
        )
        let category = TopicSource.forum(.forum(13), title: "Discussions")
        let topic = TopicSummary(topicID: TopicID(category: .forum(13), topic: 1), title: "Sujet", path: "/t1")
        root.categories.selectedSource = category
        root.categories.selectedTopic = topic
        let first = try #require(root.categories.reader(for: topic))
        first.follow(ReaderTarget(source: .topic(TopicID(category: .forum(13), topic: 1)), page: 4))
        #expect(first.linkedReader != nil)
        root.showCategoryFromFavorites(category)
        #expect(first.linkedReader == nil)
        root.categories.selectedTopic = topic
        let again = try #require(root.categories.reader(for: topic))
        #expect(again !== first)
        #expect(again.linkedReader == nil)
    }

    // #685: Bookmarks and Alertes Qualitay are lists beside the topic they open (three columns on the regular-width iPad), as
    // legacy's `usesTopicList` (`MainWindow.swift:1326-1333` @ 87fe0d1c); the other Plus entries keep two columns.
    @Test func bookmarksAndQualityAlertsAreTheTopicListPlusEntries() {
        #expect(PlusEntry.allCases.filter(\.usesTopicList) == [.bookmarks, .qualityAlerts])
        #expect(PlusEntry.bookmarks.detailPlaceholder?.title == "Aucun bookmark sélectionné")
        #expect(PlusEntry.qualityAlerts.detailPlaceholder?.title == "Aucune alerte sélectionnée")
        #expect(PlusEntry.allCases.filter { $0.detailPlaceholder != nil } == [.bookmarks, .qualityAlerts])
    }

    // #685: each topic-list entry keeps the topic it opened in the detail column; an entry without a list opens nothing there.
    @Test func eachTopicListEntryKeepsItsOwnDetailReader() {
        let root = model(initial: .plus(.qualityAlerts))
        let target = ReaderTarget(source: .topic(TopicID(category: .forum(13), topic: 7)))
        let alert = TopicReaderModel(target: target, title: "Alerte", source: FakeTopicPages())
        let bookmark = TopicReaderModel(target: target, title: "Bookmark", source: FakeTopicPages())
        root.openInDetail(alert, for: .qualityAlerts)
        root.openInDetail(bookmark, for: .bookmarks)
        root.openInDetail(TopicReaderModel(target: target, title: "Réglages", source: FakeTopicPages()), for: .settings)
        #expect(root.detailReaders[.qualityAlerts] === alert)
        #expect(root.detailReaders[.bookmarks] === bookmark)
        #expect(root.detailReaders[.settings] == nil)

        // Another alert replaces the reader and closes what a link had pushed over the old one (#512 on this column).
        alert.follow(ReaderTarget(source: .topic(TopicID(category: .forum(13), topic: 8))))
        #expect(alert.linkedReader != nil)
        let next = TopicReaderModel(target: target, title: "Autre alerte", source: FakeTopicPages())
        root.openInDetail(next, for: .qualityAlerts)
        #expect(alert.linkedReader == nil)
        #expect(root.detailReaders[.qualityAlerts] === next)
    }

    // LOT-132: deleting the bookmark shown beside the list empties the detail column (legacy `MainWindow.swift:2266-2271`).
    @Test func closingADetailColumnShowsItsPlaceholderAgain() {
        let root = model(initial: .plus(.bookmarks))
        let target = ReaderTarget(source: .topic(TopicID(category: .forum(13), topic: 7)))
        let bookmark = TopicReaderModel(target: target, title: "Bookmark", source: FakeTopicPages())
        let alert = TopicReaderModel(target: target, title: "Alerte", source: FakeTopicPages())
        root.openInDetail(bookmark, for: .bookmarks)
        root.openInDetail(alert, for: .qualityAlerts)
        bookmark.follow(ReaderTarget(source: .topic(TopicID(category: .forum(13), topic: 8))))
        #expect(bookmark.linkedReader != nil)

        root.closeDetail(for: .bookmarks)
        #expect(root.detailReaders[.bookmarks] == nil)
        #expect(bookmark.linkedReader == nil)
        #expect(root.detailReaders[.qualityAlerts] === alert)
    }
}
