import HFRModels
import HFRStorage
@testable import SwiftHFR
import Testing

/// Re-selecting the current tab reloads its list with a light haptic (UXD-04, GAP-007, #426); the reader is left alone.
@MainActor
struct TabReselectTests {
    private final class Recorder {
        var played: [HapticFeedback.Kind] = []
    }

    private struct Rig {
        let root: RootModel
        let lists: FakeDataSource
        let messages: FakePrivateMessages
        let recorder: Recorder
    }

    private func rig(settings: [String: SettingRawValue] = [:]) -> Rig {
        let source = FakeDataSource()
        let privateMessages = FakePrivateMessages()
        let recorder = Recorder()
        let store = InMemorySettingsStore(settings)
        let forums = ForumListModel(dataSource: source)
        let root = RootModel(
            forums: forums,
            categories: NavigationModel(dataSource: source, forums: forums, startupSource: RootModel.categoriesStartupSource),
            favorites: NavigationModel(dataSource: source, forums: forums, startupSource: .flagged),
            messages: MessageListModel(source: privateMessages, isLoggedIn: { true }), store: store,
            initial: .tab(.categories),
            haptics: HapticFeedback(store: store) { recorder.played.append($0) }
        )
        return Rig(root: root, lists: source, messages: privateMessages, recorder: recorder)
    }

    @Test func categoriesReloadsTheForumListWithAHaptic() async {
        let rig = rig()
        await rig.root.reselect(.categories)
        #expect(rig.lists.requests == ["forums"])
        #expect(rig.recorder.played == [.impact(.light)])
    }

    @Test func categoriesAlsoReloadsTheTopicListOnScreen() async {
        let rig = rig()
        rig.root.categories.selectedSource = .forum(.forum(13), title: "Hardware")
        await rig.root.reselect(.categories)
        #expect(rig.lists.requests.sorted() == ["forums", "topics:13:1"])
        #expect(rig.recorder.played == [.impact(.light)])
    }

    @Test func favoritesReloadsItsListAndNotTheForumList() async {
        let rig = rig()
        await rig.root.reselect(.favorites)
        #expect(rig.lists.requests.count == 1)
        #expect(rig.lists.requests.first?.hasPrefix("favorites:") == true)
        #expect(rig.recorder.played == [.impact(.light)])
    }

    // Legacy's Favoris list alone listens (`Favorites.swift:785-794` @ 87fe0d1c): the category pushed over it listens to the
    // Catégories tab's re-selection (`MainWindow.swift:893-900`).
    @Test func favoritesDoesNotReloadTheCategoryPushedOverIt() async {
        let rig = rig()
        rig.root.favorites.openedCategory = .forum(.forum(13), title: "Hardware")
        await rig.root.reselect(.favorites)
        #expect(!rig.lists.requests.contains("topics:13:1"))
        #expect(rig.lists.requests.contains { $0.hasPrefix("favorites:") })
    }

    @Test func messagesReloadsTheCurrentPage() async {
        let rig = rig()
        await rig.root.reselect(.messages)
        #expect(rig.messages.requests == [1])
        #expect(rig.recorder.played == [.impact(.light)])
    }

    @Test func plusAndRechercheDoNothing() async {
        let rig = rig()
        await rig.root.reselect(.more)
        await rig.root.reselect(.search)
        #expect(rig.lists.requests.isEmpty)
        #expect(rig.messages.requests.isEmpty)
        #expect(rig.recorder.played.isEmpty)
    }

    @Test func theHapticSettingSilencesTheHapticButNotTheReload() async {
        let rig = rig(settings: ["haptics": .bool(false)])
        await rig.root.reselect(.messages)
        #expect(rig.messages.requests == [1])
        #expect(rig.recorder.played.isEmpty)
    }

    @Test func theTabBarIndexNamesTheTab() {
        #expect(RootTab.barOrder(hasSearch: false) == [.categories, .favorites, .messages, .more])
        #expect(RootTab.barOrder(hasSearch: true) == [.categories, .favorites, .messages, .search, .more])
    }

    @Test func tappingTheSelectedSidebarRowReselectsIt() async throws {
        let rig = rig()
        rig.root.selectedDestination = .tab(.messages)
        let task = try #require(rig.root.selectFromSidebar(.tab(.messages)))
        await task.value
        #expect(rig.messages.requests == [1])
        #expect(rig.recorder.played == [.impact(.light)])
    }

    @Test func tappingAnotherSidebarRowOnlySelectsIt() {
        let rig = rig()
        #expect(rig.root.selectFromSidebar(.tab(.favorites)) == nil)
        #expect(rig.root.selectedDestination == .tab(.favorites))
        #expect(rig.recorder.played.isEmpty)
    }

    @Test func aSidebarTapOnPlusSelectsItsEntryAlthoughPlusIsTheSelectedTab() {
        let rig = rig()
        rig.root.selectedDestination = .tab(.more)
        // The sidebar shows Plus as Réglages: that row is not the selected destination, so it is a selection.
        #expect(rig.root.selectFromSidebar(.plus(.settings)) == nil)
        #expect(rig.root.selectedDestination == .plus(.settings))
        #expect(rig.recorder.played.isEmpty)
    }
}
