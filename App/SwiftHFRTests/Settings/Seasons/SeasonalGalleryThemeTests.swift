import HFRModels
import HFRStorage
@testable import SwiftHFR
import Testing
import UIKit

/// Noël soft with LOT-188's theme engine (LOT-166; operator decision (a), 2026-11-12, THEMES.md §5): the overlay paints legacy's
/// red over Legacy only, a gallery theme keeps its own accent (and gets the snow and the crossings); the saved previous theme
/// is the stored `theme_id`, and restoring never writes it.
@MainActor
struct SeasonalGalleryThemeTests {
    private func rgb(_ color: UIColor, dark: Bool) -> [Int] {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.resolvedColor(with: UITraitCollection(userInterfaceStyle: dark ? .dark : .light))
            .getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return [red, green, blue].map { Int(($0 * 255).rounded()) }
    }

    @Test func overAGalleryThemeTheOverlayKeepsTheThemesAccent() throws {
        let catalog = try ThemeFixtures.catalog()
        let model = ThemeSettingsModel(store: InMemorySettingsStore(), catalog: catalog)
        model.select(try #require(catalog.themes.first { $0.id == "test-theme" }))
        let noel = model.appearance.applying(.noelSoft)
        // Nothing of the overlay under a gallery theme: no red stored in the appearance, none in the reader's variables.
        #expect(noel == model.appearance)
        #expect(noel.readerVariables.map(\.value) == model.appearance.readerVariables.map(\.value))
        // The test theme's accentText: #0057B8 light, #FFC040 dark.
        #expect(rgb(noel.accentUIColor, dark: false) == [0x00, 0x57, 0xB8])
        #expect(rgb(noel.accentUIColor, dark: true) == [0xFF, 0xC0, 0x40])
        #expect(noel.screenFill == model.appearance.screenFill)
    }

    @Test func overLegacyTheOverlayIsLegacysRed() {
        let model = ThemeSettingsModel(store: InMemorySettingsStore())
        let noel = model.appearance.applying(.noelSoft)
        #expect(rgb(noel.accentUIColor, dark: false) == [0xFF, 0x00, 0x00])
        #expect(rgb(noel.accentUIColor, dark: true) == [0xFF, 0x00, 0x00])
    }

    /// The saved previous theme is the stored `theme_id`; « Désactiver » drops it and never writes `theme_id`: a theme the
    /// user picked meanwhile stays (a write-back of the saved id would bring "test-theme" back).
    @Test func switchingOnSavesTheStoredThemeIDAndRestoringLeavesItAlone() {
        let clock = SeasonTestClock(1, 12, 2026)
        let store = InMemorySettingsStore()
        store.set("test-theme", for: SettingKey.themeID)
        let model = clock.model(store: store)
        model.sceneDidBecomeActive()
        #expect(model.activeTheme == .noelSoft)
        #expect(store.value(for: SettingKey.noelPreviousThemeID(year: 2026)) == "test-theme")
        store.set("other-theme", for: SettingKey.themeID)
        model.answerArrival(disable: true)
        #expect(model.activeTheme == nil)
        #expect(store.value(for: SettingKey.noelPreviousThemeID(year: 2026)) == nil)
        #expect(store.value(for: SettingKey.themeID) == "other-theme")
    }

    /// Packing restores without writing `theme_id` either: a pick of 10/12 survives 27/12.
    @Test func packingLeavesAThemePickedDuringTheSeasonAlone() {
        let clock = SeasonTestClock(1, 12, 2026)
        let store = InMemorySettingsStore()
        store.set("test-theme", for: SettingKey.themeID)
        clock.model(store: store).sceneDidBecomeActive()
        clock.move(to: 10, 12, 2026)
        store.set("other-theme", for: SettingKey.themeID)
        clock.move(to: 27, 12, 2026)
        let model = clock.model(store: store)
        model.sceneDidBecomeActive()
        #expect(model.activeTheme == nil)
        #expect(store.value(for: SettingKey.noelPreviousThemeID(year: 2026)) == nil)
        #expect(store.value(for: SettingKey.themeID) == "other-theme")
    }

    @Test func noStoredThemeIsSavedAsLegacy() {
        let clock = SeasonTestClock(1, 12, 2026)
        let store = InMemorySettingsStore()
        clock.model(store: store).sceneDidBecomeActive()
        #expect(store.value(for: SettingKey.noelPreviousThemeID(year: 2026)) == ThemeDefinition.legacyID)
        #expect(store.value(for: SettingKey.themeID) == nil)
    }

    /// A season switched on by PR 1's build saved "legacy": it still reads as on, and packing restores it.
    @Test func aSeasonSavedByTheFirstBuildStillReadsAndRestores() {
        let clock = SeasonTestClock(10, 12, 2026)
        let store = InMemorySettingsStore()
        store.set("legacy", for: SettingKey.noelPreviousThemeID(year: 2026))
        store.set(2026, for: SettingKey.noelActiveYear)
        store.set(true, for: SettingKey.noelArrivalShown(year: 2026))
        let model = clock.model(store: store)
        #expect(model.activeTheme == .noelSoft)
        clock.move(to: 27, 12, 2026)
        model.sceneDidBecomeActive()
        #expect(model.activeTheme == nil)
        #expect(store.value(for: SettingKey.noelPreviousThemeID(year: 2026)) == nil)
        #expect(store.value(for: SettingKey.noelActiveYear) == nil)
    }
}
