import Foundation
import HFRModels
import HFRStorage
@testable import SwiftHFR
import Testing

/// Turning a seasonal theme off gives back the user's theme and accent exactly (LOT-166 acceptance): Noël soft is drawn over the
/// "Thème" settings and never writes them.
@MainActor
struct SeasonalThemeRestoreTests {
    /// A user with every "Thème" key set away from its default.
    static func customisedStore() -> InMemorySettingsStore {
        let store = InMemorySettingsStore()
        let theme = ThemeSettingsModel(store: store)
        theme.mode = .dark
        theme.accentHue = 0.42
        theme.darkStyle = .oled
        theme.darkBrightness = 0.8
        return store
    }

    /// The raw value of every fixed key of the catalogue.
    static func snapshot(_ store: any SettingsStore) -> [String: SettingRawValue?] {
        Dictionary(uniqueKeysWithValues: SettingKey.allKeys.map { ($0, store.rawValue(forKey: $0)) })
    }

    @Test func desactiverAtTheArrivalLeavesEveryThemeKeyAsItWas() {
        let store = Self.customisedStore()
        let before = Self.snapshot(store)
        let appearance = ThemeSettingsModel(store: store).appearance
        let clock = SeasonTestClock(1, 12, 2026)
        let model = clock.model(store: store)
        model.sceneDidBecomeActive()
        #expect(appearance.applying(model.activeTheme) != appearance)
        model.answerArrival(disable: true)
        #expect(Self.snapshot(store) == before)
        #expect(ThemeSettingsModel(store: store).appearance == appearance)
        #expect(appearance.applying(model.activeTheme) == appearance)
    }

    @Test func packingLeavesEveryThemeKeyAsItWas() {
        let store = Self.customisedStore()
        let before = Self.snapshot(store)
        let clock = SeasonTestClock(1, 12, 2026)
        let model = clock.model(store: store)
        model.sceneDidBecomeActive()
        model.answerArrival(disable: false)
        clock.move(to: 27, 12, 2026)
        let later = clock.model(store: store)
        later.sceneDidBecomeActive()
        #expect(later.activeTheme == nil)
        #expect(Self.snapshot(store) == before)
    }

    /// Legacy's Christmas mode tinted with `.red` in both variants (`Common.swift:610-612, 625-627` @ 87fe0d1c); the rest of
    /// the appearance (dark style, brightness) is the user's.
    @Test func noelSoftHasLegacysRedAccentOverTheUsersAppearance() {
        let appearance = ThemeSettingsModel(store: Self.customisedStore()).appearance
        let noel = appearance.applying(.noelSoft)
        let red = ThemeColor(red: 1, green: 0, blue: 0)
        #expect(noel.dayAccent == red)
        #expect(noel.nightAccent == red)
        #expect(noel.darkStyle == appearance.darkStyle)
        #expect(noel.darkBrightness == appearance.darkBrightness)
        #expect(appearance.applying(nil) == appearance)
    }
}
