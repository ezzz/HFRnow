import HFRStorage
@testable import SwiftHFR
import Testing

@MainActor
struct AppIconSettingsModelTests {
    private struct Refusal: Error {}

    private final class FakeSwitcher: AlternateIconSwitching {
        var supportsAlternateIcons = true
        var fails = false
        var applied: [String?] = []
        var gate: CheckedContinuation<Void, Never>?
        var suspends = false

        func setAlternateIconName(_ name: String?) async throws {
            if suspends { await withCheckedContinuation { gate = $0 } }
            if fails { throw Refusal() }
            applied.append(name)
        }
    }

    @Test func emptyStoreShowsTheDefaultIcon() {
        #expect(AppIconSettingsModel(store: InMemorySettingsStore(), switcher: FakeSwitcher()).selection == .superblue)
    }

    @Test func aStoredLegacyValueWithArtIsShown() {
        let store = InMemorySettingsStore(["icon": .string("redface3dbig")])
        #expect(AppIconSettingsModel(store: store, switcher: FakeSwitcher()).selection == .redface3dbig)
    }

    @Test func everyLegacyValueIsAnOptionWithItsLegacyIconName() {
        let legacy: [String: String?] = [
            "superblue": nil, "classic": "Icon-CLASSIC", "classic-red": "Icon-CLASSIC-RED", "redface": "Icon-REDFACE",
            "redface-blue": "Icon-REDFACEBLUE", "beta": "Icon-BETA", "blue": "Icon-BLUE", "white": "Icon-WHITE"
        ]
        for (key, name) in legacy {
            let model = AppIconSettingsModel(store: InMemorySettingsStore(["icon": .string(key)]), switcher: FakeSwitcher())
            #expect(model.selection.rawValue == key)
            #expect(model.selection.alternateIconName == name)
        }
    }

    @Test func anUnknownStoredValueShowsTheDefaultAndStaysInTheStore() async {
        let store = InMemorySettingsStore(["icon": .string("from-the-future")])
        let model = AppIconSettingsModel(store: store, switcher: FakeSwitcher())
        #expect(model.selection == .superblue)
        await model.select(.superblue)
        #expect(store.rawValue(forKey: "icon") == .string("from-the-future"))
    }

    @Test func choosingAnIconAppliesItThenWritesTheLegacyKey() async {
        let store = InMemorySettingsStore()
        let switcher = FakeSwitcher()
        let model = AppIconSettingsModel(store: store, switcher: switcher)
        await model.select(.redface3dbig)
        #expect(switcher.applied == ["Icon-RedFace3DBig"])
        #expect(model.selection == .redface3dbig)
        #expect(store.rawValue(forKey: "icon") == .string("redface3dbig"))
        await model.select(.superblue)
        #expect(switcher.applied == ["Icon-RedFace3DBig", nil])
        #expect(store.rawValue(forKey: "icon") == .string("superblue"))
    }

    @Test func aRefusalKeepsTheSelectionAndTheStoreAndReportsInFrench() async {
        let store = InMemorySettingsStore()
        let switcher = FakeSwitcher()
        switcher.fails = true
        let model = AppIconSettingsModel(store: store, switcher: switcher)
        await model.select(.redface3dbig)
        #expect(model.selection == .superblue)
        #expect(store.rawValue(forKey: "icon") == nil)
        #expect(model.errorMessage?.hasPrefix("Impossible de changer l’icône") == true)
    }

    @Test func nothingHappensWhereAlternateIconsAreUnsupported() async {
        let switcher = FakeSwitcher()
        switcher.supportsAlternateIcons = false
        let model = AppIconSettingsModel(store: InMemorySettingsStore(), switcher: switcher)
        await model.select(.redface3dbig)
        #expect(switcher.applied.isEmpty)
        #expect(model.selection == .superblue)
    }

    @Test func aSecondChoiceWhileOneIsApplyingIsIgnored() async {
        let switcher = FakeSwitcher()
        switcher.suspends = true
        let model = AppIconSettingsModel(store: InMemorySettingsStore(), switcher: switcher)
        let first = Task { await model.select(.redface3dbig) }
        while switcher.gate == nil { await Task.yield() }
        #expect(model.isSwitching)
        await model.select(.redface3dbig)
        switcher.gate?.resume()
        await first.value
        #expect(switcher.applied == ["Icon-RedFace3DBig"])
        #expect(!model.isSwitching)
        #expect(model.errorMessage == nil)
    }
}
