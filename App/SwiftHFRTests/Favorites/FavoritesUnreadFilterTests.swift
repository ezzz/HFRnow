import Foundation
import HFRModels
import HFRStorage
@testable import SwiftHFR
import Testing

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
}
