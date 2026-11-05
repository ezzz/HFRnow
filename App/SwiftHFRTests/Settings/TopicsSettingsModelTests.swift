import HFRModels
import HFRStorage
@testable import SwiftHFR
import Testing

@MainActor
struct TopicsSettingsModelTests {
    @Test func emptyStoreShowsTheLegacyDefaults() {
        let model = TopicsSettingsModel(store: InMemorySettingsStore())
        #expect(model.messageStyle == .modern)
        #expect(!model.showsSignatures)
        #expect(model.swipesPages)
    }

    @Test func storedLegacyValuesAreShown() {
        let store = InMemorySettingsStore([
            "theme_style": .int(0), "display_sig": .string("yes"), "topic_page_swipe_navigation": .bool(false)
        ])
        let model = TopicsSettingsModel(store: store)
        #expect(model.messageStyle == .classic)
        #expect(model.showsSignatures)
        #expect(!model.swipesPages)
    }

    @Test func everyChangeIsWrittenUnderItsLegacyKeyAndShape() {
        let store = InMemorySettingsStore()
        let model = TopicsSettingsModel(store: store)
        #expect(store.rawValue(forKey: "theme_style") == nil) // creating writes nothing
        model.messageStyle = .classic
        model.showsSignatures = true
        model.swipesPages = false
        #expect(store.rawValue(forKey: "theme_style") == .int(0))
        #expect(store.rawValue(forKey: "display_sig") == .string("yes"))
        #expect(store.rawValue(forKey: "topic_page_swipe_navigation") == .bool(false))
    }
}
