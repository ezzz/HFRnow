import HFRStorage
import SwiftUI

// Port of HFRswift/Swift/HFRswiftApp.swift (HFRswiftApp) @ 2440d79. Differences: no ObjC app delegate; HFRKit is the engine.
/// Entry point of the SwiftHFR iOS app; the composition root for every screen.
@main
struct SwiftHFRApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var accounts = AccountsModel.live()
    /// The "Général" settings, shared by the settings screen and every screen that reads the type scale and density.
    @State private var general: GeneralSettingsModel
    /// The "Thème" settings: appearance and colours of every screen and of the reader (LOT-121).
    @State private var theme: ThemeSettingsModel
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Settings keep their legacy keys: clamp an unknown theme mode and migrate the old text size once (LOT-060).
        _ = LegacySettingsNormalizer.run(on: UserDefaultsSettingsStore())
        // Created after the migration, so it reads the migrated text size.
        _general = State(initialValue: GeneralSettingsModel(
            store: UserDefaultsSettingsStore(), rotationChanged: { OrientationPolicy.refresh() }
        ))
        _theme = State(initialValue: ThemeSettingsModel(store: UserDefaultsSettingsStore()))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(accounts)
                .environment(general)
                // One type scale and one list density for every screen, live (LOT-169).
                .appTypography(general.textScale, density: general.listDensity)
                .appTheme(theme)
                // Restores the stored accounts and their sessions once per launch (LOT-081).
                .task { await accounts.restore() }
                // Back in the foreground: sessions the forum did not confirm are checked again, quietly (#300).
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task { await accounts.recheckUnconfirmedSessions() }
                }
        }
    }
}
