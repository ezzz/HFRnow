import HFRModels
@testable import SwiftHFR
import Testing

struct FavoritesPresentationTests {
    private let grouped = FavoritesLayoutOptions(groupedByCategory: true, showsCollapsedSections: false, showsEmptySections: false)

    private func page() -> FavoritesPage {
        FavoritesPage(sections: [
            favoriteSection(1, [favoriteTopic(1, category: 1, day: 1), favoriteTopic(2, category: 1, day: 5)]),
            favoriteSection(2, []),
            favoriteSection(3, [favoriteTopic(3, category: 3, day: 3)])
        ])
    }

    private func ids(_ groups: [TopicGroup]) -> [String] { groups.map(\.id) }

    @Test func groupedKeepsPageOrderAndDropsEmptyCategories() {
        let groups = FavoritesPresentation.groups(of: page(), options: grouped, collapsed: [], superFavorites: [])
        #expect(ids(groups) == ["cat:1", "cat:3"])
        #expect(groups.map(\.topics.count) == [2, 1])
        #expect(groups.allSatisfy { $0.isCollapsible && !$0.isCollapsed })
    }

    @Test func emptyCategoriesShowWhenAsked() {
        var options = grouped
        options.showsEmptySections = true
        let groups = FavoritesPresentation.groups(of: page(), options: options, collapsed: [], superFavorites: [])
        #expect(ids(groups) == ["cat:1", "cat:2", "cat:3"])
        #expect(groups[1].isCollapsible == false)
    }

    @Test func aCollapsedSectionIsHiddenUnlessCollapsedSectionsShow() {
        let hidden = FavoritesPresentation.groups(of: page(), options: grouped, collapsed: ["cat:1"], superFavorites: [])
        #expect(ids(hidden) == ["cat:3"])
        var options = grouped
        options.showsCollapsedSections = true
        let shown = FavoritesPresentation.groups(of: page(), options: options, collapsed: ["cat:1"], superFavorites: [])
        #expect(ids(shown) == ["cat:1", "cat:3"])
        #expect(shown[0].isCollapsed)
        #expect(shown[0].topics.count == 2)
        #expect(!shown[1].isCollapsed)
    }

    @Test func aCollapsedEmptyCategoryIsNotFoldedWhenShown() {
        var options = grouped
        options.showsCollapsedSections = true
        options.showsEmptySections = true
        let groups = FavoritesPresentation.groups(of: page(), options: options, collapsed: ["cat:2"], superFavorites: [])
        #expect(groups.first { $0.id == "cat:2" }?.isCollapsed == false)
    }

    @Test func superFavouritesLeadAndLeaveTheirCategory() {
        let supers: Set<TopicID> = [TopicID(category: .forum(1), topic: 2), TopicID(category: .forum(3), topic: 3)]
        let groups = FavoritesPresentation.groups(of: page(), options: grouped, collapsed: [], superFavorites: supers)
        #expect(ids(groups) == ["super-favorites", "cat:1"])
        #expect(groups[0].topics.map(\.title) == ["Sujet 2", "Sujet 3"])
        #expect(groups[1].topics.map(\.title) == ["Sujet 1"])
    }

    @Test func aTopicNumberInAnotherCategoryIsNotASuperFavourite() {
        let supers: Set<TopicID> = [TopicID(category: .forum(99), topic: 1)]
        let groups = FavoritesPresentation.groups(of: page(), options: grouped, collapsed: [], superFavorites: supers)
        #expect(ids(groups) == ["cat:1", "cat:3"])
    }

    @Test func flatListsEveryTopicByLastPostAndIgnoresFolding() {
        var options = grouped
        options.groupedByCategory = false
        let supers: Set<TopicID> = [TopicID(category: .forum(1), topic: 1)]
        let groups = FavoritesPresentation.groups(of: page(), options: options, collapsed: ["cat:1"], superFavorites: supers)
        #expect(ids(groups) == ["topics"])
        #expect(groups[0].title == nil)
        #expect(groups[0].topics.map(\.title) == ["Sujet 2", "Sujet 3", "Sujet 1"])
        #expect(FavoritesPresentation.groups(of: FavoritesPage(), options: options, collapsed: [], superFavorites: []).isEmpty)
    }

    @Test func foldableSectionsAreThoseWithATopicOutsideTheSuperFavourites() {
        #expect(FavoritesPresentation.collapsibleSectionIDs(of: page(), superFavorites: []) == ["cat:1", "cat:3"])
        let supers: Set<TopicID> = [TopicID(category: .forum(3), topic: 3)]
        #expect(FavoritesPresentation.collapsibleSectionIDs(of: page(), superFavorites: supers) == ["cat:1"])
    }
}
