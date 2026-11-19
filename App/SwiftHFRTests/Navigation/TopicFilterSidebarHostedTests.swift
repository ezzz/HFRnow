import HFRModels
import HFRNetwork
import HFRStorage
@testable import SwiftHFR
import SwiftUI
import Testing
import UIKit

/// #870, the iPad route: on the regular-width split every forum list goes through `CategoriesSidebarColumn`, which builds its own
/// `TopicListView` (`RootSidebarView.swift`), apart from the `TopicsColumn` the iPhone tabs use. Each filter must reach the same
/// `TopicRowView` there too (`MainWindow.swift:513-518` @ 87fe0d1c).
/// One suite with `TopicFilterListHostedTests` (an extension of it): both count the same fixtures' row builds, so they must not
/// run in parallel.
extension TopicFilterListHostedTests {
    private func environment(data: FakeDataSource) -> AppEnvironment {
        let pages = FakeTopicPages { _ in readerPage(page: 1) }
        return AppEnvironment(
            session: HFRSession(), dataSource: data, visibility: ForumVisibility(), currentAccountName: nil, topicPages: pages,
            reader: ReaderServices(
                imageFetcher: ReaderImageFetcher(transport: MockTransport(replies: [])),
                settings: ReaderSettings(
                    autoLoadsThirdPartyImages: { false }, renderOptions: { ReaderRenderOptions() }, swipesPages: { false }
                ),
                profiles: FakeUserProfiles([])
            ),
            privateMessages: FakePrivateMessages(), composer: nil, filteredPosts: .unavailable,
            favoriteStores: FavoritesStores(
                layout: FavoritesLayoutStore(persistence: InMemorySmallStorePersistence()),
                superFavorites: SuperFavoritesStore(persistence: InMemorySmallStorePersistence()), account: nil
            ),
            flagActions: nil, memberAvatars: nil,
            pseudoListsSnapshot: PseudoListsSnapshot(store: PseudoListStore(persistence: InMemoryPseudoListPersistence()), account: nil),
            blocklistChanges: nil, privateMessageCount: nil
        )
    }

    @Test(
        "On the iPad sidebar every filter draws its topics through TopicRowView (#870)",
        arguments: FilterCapture.allCases, [UIUserInterfaceStyle.light, .dark]
    )
    func everyFilterUsesTheSharedRowOnTheSidebar(filter: FilterCapture, style: UIUserInterfaceStyle) async throws {
        let page = try filter.page()
        let data = FakeDataSource()
        data.topicHandler = { _, _ in page }
        let topicFilter = TopicFilterModel(settings: InMemorySettingsStore())
        topicFilter.flag = filter.flag
        let forums = ForumListModel(dataSource: data)
        let root = RootModel(
            forums: forums,
            categories: NavigationModel(dataSource: data, forums: forums, sessionIsLoggedIn: { true }, topicFilter: topicFilter),
            favorites: NavigationModel(
                dataSource: data, forums: forums, sessionIsLoggedIn: { true }, startupSource: TopicSource(mode: .flagsAndFavorites)
            ),
            messages: MessageListModel(source: FakePrivateMessages()),
            store: InMemorySettingsStore(), initial: .tab(.categories)
        )
        let view = RootSidebarView(model: root, environment: environment(data: data))
            .environment(makeModel(store: InMemoryCredentialStore()))
            .environment(ExperimentalSettings(store: InMemorySettingsStore()))
        let scene = try #require(UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 1366, height: 1024)
        window.overrideUserInterfaceStyle = style
        let host = UIHostingController(rootView: view)
        host.traitOverrides.horizontalSizeClass = .regular
        window.rootViewController = host
        window.isHidden = false
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        // Row builds are counted per topic id and ids repeat across runs: read what this run adds.
        let baseline = TopicRowView.builds
        root.categories.selectedSource = .forum(.forum(13), title: "Discussions")
        for _ in 0..<60 {
            try await Task.sleep(for: .milliseconds(50))
            window.layoutIfNeeded()
        }
        for topic in page.topics {
            #expect((TopicRowView.builds[topic.id] ?? 0) > (baseline[topic.id] ?? 0), "no TopicRowView build for \(topic.id)")
        }
        if filter == .read { #expect(!page.topics.isEmpty) }
    }
}
