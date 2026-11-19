import HFRModels
import HFRStorage
@testable import SwiftHFR
import Testing

/// #1195: the current session changed in place (a re-login keeps the session object, so the root is not rebuilt). The root
/// reads the home page again, then the lists of both tabs, unless the change is an expiry the home page already shows.
@MainActor
struct RootModelSessionChangeTests {
    private struct Rig {
        let source: FakeDataSource
        let loggedIn: LoginFlag
        let root: RootModel
    }

    /// A root whose Catégories tab shows category 13 and whose Favoris tab shows the flags, both loaded logged out.
    private func rig() async -> Rig {
        let source = FakeDataSource()
        let loggedIn = LoginFlag()
        loggedIn.value = false
        source.forumHandler = { ForumListPage(forums: [], isLoggedIn: loggedIn.value) }
        let forums = ForumListModel(dataSource: source)
        let session: @Sendable () async -> Bool = { loggedIn.value }
        let filter = TopicFilterModel(settings: InMemorySettingsStore([SettingKey.topicListFlag.key: .int(1)]))
        let root = RootModel(
            forums: forums,
            categories: NavigationModel(
                dataSource: source, forums: forums, sessionIsLoggedIn: session, startupSource: .forum(.forum(13), title: "A"),
                topicFilter: filter
            ),
            favorites: NavigationModel(
                dataSource: source, forums: forums, sessionIsLoggedIn: session, startupSource: RootModel.favoritesStartupSource
            ),
            messages: MessageListModel(source: FakePrivateMessages()),
            store: InMemorySettingsStore(), initial: .tab(.categories)
        )
        await forums.loadIfNeeded()
        await root.categories.topicList(for: .forum(.forum(13), title: "A")).onAppear()
        await root.favorites.topicList(for: .flagged).onAppear()
        return Rig(source: source, loggedIn: loggedIn, root: root)
    }

    @Test func aReloginInPlaceReloadsTheHomePageThenTheListsOfBothTabs() async {
        let rig = await rig()
        #expect(rig.source.requests == ["forums", "topics:13:1", "favorites:1"])
        rig.loggedIn.value = true
        await rig.root.currentSessionChanged(expired: false)
        #expect(rig.source.requests == ["forums", "topics:13:1", "favorites:1", "forums", "topics:13:1:owntopic=3", "favorites:1"])
        #expect(rig.root.categories.topicList(for: .forum(.forum(13), title: "A")).offersFilter)
    }

    @Test func anExpiryTheHomePageAlreadyShowsSendsNothing() async {
        let rig = await rig()
        await rig.root.currentSessionChanged(expired: true)
        #expect(rig.source.requests == ["forums", "topics:13:1", "favorites:1"])
    }
}
