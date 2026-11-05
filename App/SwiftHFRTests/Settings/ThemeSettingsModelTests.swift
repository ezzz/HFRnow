import HFRModels
import HFRStorage
@testable import SwiftHFR
import SwiftUI
import Testing

/// The "Thème" settings (LOT-121) over the legacy keys: what an update from the legacy app shows, and what each change writes.
@MainActor
struct ThemeSettingsModelTests {
    @Test func emptyStoreShowsTheLegacyDefaults() {
        let model = ThemeSettingsModel(store: InMemorySettingsStore())
        #expect(model.mode == .system)
        #expect(model.preferredColorScheme == nil)
        #expect(abs(model.accentHue - 190.0 / 360.0) < 1e-9)
        #expect(model.darkBrightness == 1)
        #expect(model.appearance == .standard)
    }

    @Test(arguments: [
        (AutoThemeMode.system.rawValue, 1, ThemeSettingsModel.Mode.system),
        (AutoThemeMode.manual.rawValue, 0, ThemeSettingsModel.Mode.light),
        (AutoThemeMode.manual.rawValue, 1, ThemeSettingsModel.Mode.dark)
    ])
    func theLegacyAppearanceKeysAreRead(autoTheme: Int, theme: Int, expected: ThemeSettingsModel.Mode) {
        let model = ThemeSettingsModel(store: InMemorySettingsStore(["auto_theme": .int(autoTheme), "theme": .int(theme)]))
        #expect(model.mode == expected)
    }

    @Test func aManualThemeForcesItsSchemeAndSurvivesARelaunch() {
        let store = InMemorySettingsStore()
        let model = ThemeSettingsModel(store: store)
        model.mode = .dark
        #expect(model.preferredColorScheme == .dark)
        #expect(store.rawValue(forKey: "auto_theme") == .int(0))
        #expect(store.rawValue(forKey: "theme") == .int(1))
        // A relaunch reads the same store.
        #expect(ThemeSettingsModel(store: store).preferredColorScheme == .dark)

        model.mode = .light
        #expect(ThemeSettingsModel(store: store).preferredColorScheme == .light)
        model.mode = .system
        #expect(store.rawValue(forKey: "auto_theme") == .int(3))
        // Following iOS keeps the manual variant, as legacy did.
        #expect(store.rawValue(forKey: "theme") == .int(0))
        #expect(ThemeSettingsModel(store: store).preferredColorScheme == nil)
    }

    @Test func storedLegacyColoursAndBrightnessAreShown() {
        let store = InMemorySettingsStore([
            "theme_day_color_action": .string("{1.000, 0.350, 0.350, 1.000}"),
            "theme_night_color_action": .string("{0.200, 0.400, 0.600, 1.000}"),
            "theme_night_brightness": .double(0.4)
        ])
        let model = ThemeSettingsModel(store: store)
        // The slider shows the light accent's hue (red), whatever the dark accent holds.
        #expect(model.accentHue < 0.001)
        #expect(model.appearance.dayAccent == ThemeColor(red: 1, green: 0.35, blue: 0.35))
        #expect(model.appearance.nightAccent == ThemeColor(red: 0.2, green: 0.4, blue: 0.6))
        #expect(model.darkBrightness == 0.4)
    }

    @Test func aHueChangeWritesBothAccentsInTheLegacyShape() {
        let store = InMemorySettingsStore()
        let model = ThemeSettingsModel(store: store)
        model.accentHue = 0
        // Legacy: day = hue, s 0.65, b 1; night = hue, s 0.70, b 0.95.
        #expect(store.rawValue(forKey: "theme_day_color_action") == .string("{1.000, 0.350, 0.350, 1.000}"))
        #expect(store.rawValue(forKey: "theme_night_color_action") == .string("{0.950, 0.285, 0.285, 1.000}"))
        #expect(ThemeSettingsModel(store: store).accentHue < 0.001)
    }

    @Test func outOfRangeValuesAreClampedBeforeTheyAreStored() {
        let store = InMemorySettingsStore(["theme_night_brightness": .double(9)])
        let model = ThemeSettingsModel(store: store)
        #expect(model.darkBrightness == 1.5)
        model.darkBrightness = -2
        #expect(model.darkBrightness == 0)
        #expect(store.rawValue(forKey: "theme_night_brightness") == .double(0))
        model.accentHue = 4
        #expect(model.accentHue == 1)
    }

    @Test func creatingTheModelWritesNothing() {
        let store = InMemorySettingsStore()
        _ = ThemeSettingsModel(store: store)
        for key in ["auto_theme", "theme", "theme_day_color_action", "theme_night_color_action", "theme_night_brightness"] {
            #expect(store.rawValue(forKey: key) == nil, "\(key)")
        }
    }
}
