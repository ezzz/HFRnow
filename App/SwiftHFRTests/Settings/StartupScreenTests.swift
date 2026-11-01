import HFRModels
@testable import SwiftHFR
import Testing

@MainActor
struct StartupScreenTests {
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
