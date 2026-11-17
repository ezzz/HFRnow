import HFRStorage
@testable import SwiftHFR
import Testing

/// The fifth tab of Réglages › Expérimental › « Recherche dans la barre » (#896).
@MainActor
struct SearchTabTests {
    @Test func theOptionIsOffByDefaultAndListedUnderTheTabBar() {
        let settings = ExperimentalSettings(store: InMemorySettingsStore())
        #expect(ExperimentalFeature.searchTab.isListed)
        #expect(ExperimentalFeature.searchTab.theme == .navigation)
        #expect(!SearchTabOption.isOn(settings))
        #expect(!SearchTabOption.isOn(nil))
    }

    @Test func switchingItOnAddsTheTabAndKeepsItsKey() {
        let store = InMemorySettingsStore()
        let settings = ExperimentalSettings(store: store)
        settings.set(.searchTab, isOn: true)
        #expect(SearchTabOption.isOn(settings))
        #expect(store.rawValue(forKey: "experimental.searchTab") == .bool(true))
        #expect(SearchTabOption.isOn(ExperimentalSettings(store: store)))
    }

    /// A selection restored with the option on never points at a tab the bar lacks.
    @Test func theSearchTabFallsBackToPlusWhileTheOptionIsOff() {
        #expect(SearchTabOption.visibleTab(.search, isOn: false) == .more)
        #expect(SearchTabOption.visibleTab(.search, isOn: true) == .search)
        for tab in RootTab.allCases where tab != .search {
            #expect(SearchTabOption.visibleTab(tab, isOn: false) == tab)
            #expect(SearchTabOption.visibleTab(tab, isOn: true) == tab)
        }
    }

    @Test func theTabIsRechercheWithTheSearchSymbol() {
        #expect(RootTab.search.title == "Recherche")
        #expect(RootTab.search.symbol == PlusEntry.search.symbol)
    }
}
