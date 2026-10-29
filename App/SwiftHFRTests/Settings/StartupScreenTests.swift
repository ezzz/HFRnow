import HFRModels
@testable import SwiftHFR
import Testing

@MainActor
struct StartupScreenTests {
    @Test func favouritesOpenTheFavouritesAndOtherScreensTheForumList() {
        #expect(StartupScreen.favorites.initialSource == .favorites)
        #expect(StartupScreen.categories.initialSource == nil)
        // No private-message screen yet (LOT-126): the forum list, not a guessed destination.
        #expect(StartupScreen.messages.initialSource == nil)
    }

    @Test func theNavigationOpensOnTheStartupSource() {
        let model = NavigationModel(dataSource: FakeDataSource(), startupSource: .favorites)
        #expect(model.selectedSource == .favorites)
        #expect(model.selectedTopic == nil)
        #expect(NavigationModel(dataSource: FakeDataSource()).selectedSource == nil)
    }

    @Test func titlesAreFrench() {
        #expect(StartupScreen.allCases.map(\.title) == ["Tab Catégories", "Tab Favoris", "Tab Messages"])
    }
}
