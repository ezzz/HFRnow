import Foundation
import HFRModels
import HFRStorage
@testable import SwiftHFR
import SwiftUI
import Testing
import UIKit

/// The Favoris « Non lus / Tous » filter (#1058): the unread rule, the presentation under it, its setting and its button.
@MainActor
struct FavoritesUnreadFilterTests {
    /// A row whose flag is `behind` pages before the end of the topic (the badge of `TopicRowCues.unreadPages`); 0 = read.
    private func favorite(_ number: Int, category: Int, behind: Int, day: Int) -> TopicSummary {
        var topic = favoriteTopic(number, category: category, day: day)
        topic.pageCount = 5
        topic.flagPath = "/f\(number)"
        topic.currentPage = 5 - behind
        return topic
    }

    private func page() -> FavoritesPage {
        FavoritesPage(sections: [
            favoriteSection(1, [favorite(1, category: 1, behind: 2, day: 1), favorite(2, category: 1, behind: 0, day: 5)]),
            favoriteSection(2, [favorite(4, category: 2, behind: 0, day: 2)]),
            favoriteSection(3, [favorite(3, category: 3, behind: 1, day: 3)])
        ])
    }

    private let grouped = FavoritesLayoutOptions(
        groupedByCategory: true, showsCollapsedSections: false, showsEmptySections: false, unreadOnly: true
    )

    private func ids(_ groups: [TopicGroup]) -> [String] { groups.map(\.id) }

    @Test func aRowIsUnreadWhenItsFlagIsPagesBehind() {
        #expect(FavoritesPresentation.isUnread(favorite(1, category: 1, behind: 2, day: 1)))
        #expect(!FavoritesPresentation.isUnread(favorite(1, category: 1, behind: 0, day: 1)))
        #expect(!FavoritesPresentation.isUnread(favoriteTopic(1)), "a row without a flag link shows no badge")
    }

    @Test func allKeepsTodaysView() {
        var all = grouped
        all.unreadOnly = false
        let groups = FavoritesPresentation.groups(of: page(), options: all, collapsed: [], superFavorites: [])
        #expect(ids(groups) == ["cat:1", "cat:2", "cat:3"])
        #expect(groups.map(\.topics.count) == [2, 1, 1])
    }

    @Test func unreadKeepsOnlyUnreadRowsAndDropsSectionsLeftEmpty() {
        let groups = FavoritesPresentation.groups(of: page(), options: grouped, collapsed: [], superFavorites: [])
        #expect(ids(groups) == ["cat:1", "cat:3"])
        #expect(groups.map { $0.topics.map(\.title) } == [["Sujet 1"], ["Sujet 3"]])
    }

    @Test func aSectionLeftEmptyStaysWhenEmptySectionsShow() {
        var options = grouped
        options.showsEmptySections = true
        let groups = FavoritesPresentation.groups(of: page(), options: options, collapsed: [], superFavorites: [])
        #expect(ids(groups) == ["cat:1", "cat:2", "cat:3"])
        #expect(groups[1].topics.isEmpty)
        #expect(groups[1].isCollapsible == false)
    }

    @Test func superFavouritesFollowTheSameRule() {
        let read = TopicID(category: .forum(1), topic: 2)
        let unread = TopicID(category: .forum(3), topic: 3)
        let onlyRead = FavoritesPresentation.groups(of: page(), options: grouped, collapsed: [], superFavorites: [read])
        #expect(ids(onlyRead) == ["cat:1", "cat:3"], "a read super-favourite leaves, with no empty Super favoris section")
        let both = FavoritesPresentation.groups(of: page(), options: grouped, collapsed: [], superFavorites: [read, unread])
        #expect(ids(both) == ["super-favorites", "cat:1"])
        #expect(both[0].topics.map(\.title) == ["Sujet 3"])
        #expect(both[1].topics.map(\.title) == ["Sujet 1"])
    }

    @Test func theFlatListFiltersToo() {
        var options = grouped
        options.groupedByCategory = false
        let groups = FavoritesPresentation.groups(of: page(), options: options, collapsed: [], superFavorites: [])
        #expect(groups.map { $0.topics.map(\.title) } == [["Sujet 3", "Sujet 1"]])
        let none = FavoritesPage(sections: [favoriteSection(1, [favorite(2, category: 1, behind: 0, day: 1)])])
        #expect(FavoritesPresentation.groups(of: none, options: options, collapsed: [], superFavorites: []).isEmpty)
    }

    @Test func theChoiceDefaultsToAllAndIsWrittenUnderItsKey() {
        let store = InMemorySettingsStore()
        let options = FavoritesOptionsModel(settings: store)
        #expect(!options.unreadOnly)
        #expect(!options.layout.unreadOnly)
        #expect(store.rawValue(forKey: "favorites_unread_only") == nil, "creating the model writes nothing")
        options.unreadOnly = true
        #expect(store.rawValue(forKey: "favorites_unread_only") == .bool(true))
        #expect(options.layout.unreadOnly)
        #expect(FavoritesOptionsModel(settings: store).unreadOnly, "the choice survives a relaunch")
    }

    @Test func reloadingTheSettingsReadsTheChoiceAgain() {
        let store = InMemorySettingsStore()
        let options = FavoritesOptionsModel(settings: store)
        store.set(true, for: SettingKey.favoritesUnreadOnly)
        options.reloadSettings()
        #expect(options.unreadOnly)
    }

    @Test func theModelGroupsUnderTheChoice() {
        let options = FavoritesOptionsModel(settings: InMemorySettingsStore())
        #expect(options.groups(for: page()).count == 3)
        options.unreadOnly = true
        #expect(options.groups(for: page()).map(\.id) == ["cat:1", "cat:3"])
    }

    @Test func theButtonShowsItsStateAndTogglesTheChoice() {
        let all = FavoritesUnreadFilterButton.Content.make(unreadOnly: false)
        #expect(all.title == "Tous")
        #expect(all.symbol == "line.3.horizontal.decrease.circle")
        #expect(all.accessibilityLabel == "Afficher : tous")
        let unread = FavoritesUnreadFilterButton.Content.make(unreadOnly: true)
        #expect(unread.title == "Non lus")
        #expect(unread.symbol == "line.3.horizontal.decrease.circle.fill")
        #expect(unread.accessibilityLabel == "Afficher : non lus")
    }

    @Test func underUnreadOnlyFoldAllTouchesOnlyTheSectionsTheListShows() {
        #expect(FavoritesPresentation.collapsibleSectionIDs(of: page(), superFavorites: []) == ["cat:1", "cat:2", "cat:3"])
        #expect(FavoritesPresentation.collapsibleSectionIDs(of: page(), superFavorites: [], unreadOnly: true) == ["cat:1", "cat:3"])
        let options = FavoritesOptionsModel(settings: InMemorySettingsStore())
        options.unreadOnly = true
        #expect(options.hasCollapsibleSections(in: page()))
        let none = FavoritesPage(sections: [favoriteSection(1, [favorite(2, category: 1, behind: 0, day: 1)])])
        #expect(!options.hasCollapsibleSections(in: none), "nothing unread: no section to fold")
        #expect(!options.canCollapseMore(in: none))
    }

    private func listModel(options: FavoritesOptionsModel, page: FavoritesPage) async -> TopicListModel {
        let source = FakeDataSource()
        source.favoritesHandler = { _ in page }
        let model = TopicListModel(source: .favorites, dataSource: source, favorites: options)
        await model.loadIfNeeded()
        return model
    }

    @Test func nothingUnreadSaysSoWithNoEmptyHeaderWhateverTheEmptySectionsSetting() async {
        let options = FavoritesOptionsModel(settings: InMemorySettingsStore())
        options.showsCollapsedSections = true
        let allRead = FavoritesPage(sections: [
            favoriteSection(1, [favorite(1, category: 1, behind: 0, day: 1)]), favoriteSection(2, [])
        ])
        let model = await listModel(options: options, page: allRead)
        #expect(!model.showsNoUnreadFavorites, "« Tous »")
        #expect(model.displayedGroups.map(\.id) == ["cat:1", "cat:2"])
        options.unreadOnly = true
        #expect(model.showsNoUnreadFavorites)
        #expect(model.displayedGroups.isEmpty, "no empty header")
    }

    @Test func anUnreadRowInAFoldedSectionIsNotNothingUnread() async {
        let options = FavoritesOptionsModel(settings: InMemorySettingsStore())
        options.unreadOnly = true
        let model = await listModel(options: options, page: page())
        await options.toggleCollapsed("cat:1")
        await options.toggleCollapsed("cat:3")
        #expect(model.hasUnreadFavoriteRows)
        #expect(!model.showsNoUnreadFavorites)
        #expect(model.allSectionsHidden, "the folded-sections screen applies, not the « nothing unread » one")
    }

    @Test func removingTheLastUnreadFlagLeavesNothingUnread() async {
        let options = FavoritesOptionsModel(settings: InMemorySettingsStore())
        options.unreadOnly = true
        let onlyOne = FavoritesPage(sections: [favoriteSection(1, [favorite(1, category: 1, behind: 2, day: 1)])])
        let model = await listModel(options: options, page: onlyOne)
        #expect(model.hasUnreadFavoriteRows)
        #expect(!model.showsNoUnreadFavorites)
        model.removedFlags[favorite(1, category: 1, behind: 2, day: 1).id] = 1
        #expect(!model.hasUnreadFavoriteRows)
        #expect(model.showsNoUnreadFavorites)
        #expect(model.displayedGroups.isEmpty)
    }

    @Test func theToggleFlipsTheChoiceBothWays() {
        let options = FavoritesOptionsModel(settings: InMemorySettingsStore())
        options.toggleUnreadOnly()
        #expect(options.unreadOnly)
        options.toggleUnreadOnly()
        #expect(!options.unreadOnly)
    }

    /// The button is drawn in a top bar, on its trailing side, and a tap on it flips the choice. Reads the shown controls of the
    /// bar (SwiftUI's toolbar does not fill `rightBarButtonItems` reliably: see `AccountMenuPlacementTests`) and reports them.
    @Test func theButtonIsInTheBarAndATapTogglesTheChoice() async throws {
        let options = FavoritesOptionsModel(settings: InMemorySettingsStore())
        let scene = try #require(UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene)
        let root = NavigationStack {
            Text("Racine").toolbar { ToolbarItem(placement: .topBarTrailing) { FavoritesUnreadFilterButton(options: options) } }
        }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = UIHostingController(rootView: root)
        window.isHidden = false
        defer { window.isHidden = true }
        var control: UIControl?
        var seen = ""
        for _ in 0..<100 {
            try? await Task.sleep(for: .milliseconds(50))
            window.layoutIfNeeded()
            let bars = Self.views(in: window).compactMap { $0 as? UINavigationBar }
            let controls = bars.flatMap { bar in
                Self.views(in: bar).compactMap { $0 as? UIControl }.filter { Self.isShown($0, below: bar) && !$0.bounds.isEmpty }
                    .filter { bar.convert($0.bounds, from: $0).midX > bar.bounds.midX }
            }
            seen = "\(bars.count) bar(s), right controls: "
                + controls.map { "\(type(of: $0)) events \($0.allControlEvents.rawValue) targets \($0.allTargets.count)" }.description
            control = controls.first
            if control != nil { break }
        }
        print("FavoritesUnreadFilterTests button: \(seen)")
        let button = try #require(control, "no control on the right of the bar: \(seen)")
        button.sendActions(for: .primaryActionTriggered)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(options.unreadOnly, "a tap did not flip the choice: \(seen)")
    }

    /// In the window, with no hidden or transparent view between it and `bar` (UIKit keeps transition copies at alpha 0).
    private static func isShown(_ view: UIView, below bar: UIView) -> Bool {
        guard view.window != nil else { return false }
        var current: UIView? = view
        while let node = current, node !== bar {
            if node.isHidden || node.alpha <= 0.01 { return false }
            current = node.superview
        }
        return current === bar
    }

    private static func views(in view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap { views(in: $0) }
    }
}
