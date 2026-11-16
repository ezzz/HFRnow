import HFRStorage
@testable import SwiftHFR
import SwiftUI
import Testing
import UIKit

/// Noël soft at the app root, in a real window (LOT-166): the window tint, which UIKit chrome reads, turns red when the theme
/// is picked and goes back to the user's accent when it is turned off, live.
@MainActor
@Suite(.serialized)
struct SeasonalAppThemeTests {
    private struct Root: View {
        let theme: ThemeSettingsModel
        let seasonal: SeasonalThemeModel
        var body: some View { Color.clear.appTheme(theme, seasonal: seasonal.activeTheme) }
    }

    func until(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<500 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return condition()
    }

    @Test func pickingNoelSoftTintsTheWindowRedAndTurningItOffGivesTheAccentBack() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as? UIWindowScene)
        // A blue accent in both variants.
        let store = InMemorySettingsStore([
            "theme_day_color_action": .string("{0.000, 0.000, 1.000, 1.000}"),
            "theme_night_color_action": .string("{0.000, 0.000, 1.000, 1.000}")
        ])
        let clock = SeasonTestClock(10, 12, 2026)
        let seasonal = clock.model(store: store)
        seasonal.isAutomatic = false
        seasonal.sceneDidBecomeActive()
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 300, height: 300)
        window.rootViewController = UIHostingController(rootView: Root(theme: ThemeSettingsModel(store: store), seasonal: seasonal))
        window.isHidden = false
        defer { window.isHidden = true }
        func tint(is color: UIColor) -> Bool {
            window.tintColor?.resolvedColor(with: window.traitCollection).isEqual(color) == true
        }
        let blue = UIColor(red: 0, green: 0, blue: 1, alpha: 1)
        let red = UIColor(red: 1, green: 0, blue: 0, alpha: 1)
        #expect(await until { tint(is: blue) }, "the user's accent first")
        seasonal.select(.noelSoft)
        #expect(await until { tint(is: red) }, "Noël soft's red")
        seasonal.select(nil)
        #expect(await until { tint(is: blue) }, "the user's accent again")
    }
}
