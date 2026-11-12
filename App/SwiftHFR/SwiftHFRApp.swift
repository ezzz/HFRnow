import HFRStorage
import SwiftUI

// Port of HFRswift/Swift/HFRswiftApp.swift (HFRswiftApp) @ 2440d79. Differences: no ObjC app delegate; HFRKit is the engine.
/// Entry point of the SwiftHFR iOS app; the composition root for every screen.
@main
struct SwiftHFRApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var accounts: AccountsModel
    /// The deletion screen's wipe (LOT-157), app-wide: erasing the current account rebuilds the root navigation.
    @State private var deletion: AccountDeletionModel
    /// The legacy import (LOT-158): at launch before the accounts are read, then at each change of the current account.
    @State private var legacyImport = LegacyImportModel(importer: LegacyImportServices.liveImporter)
    /// Bumped when the avatar cache gets a file, so MP rows read it again (GAP-227).
    @State private var avatarRefresh = AvatarRefresh()
    /// The "Général" settings, shared by the settings screen and every screen that reads the type scale and density.
    @State private var general: GeneralSettingsModel
    /// The "Thème" settings: appearance and colours of every screen and of the reader (LOT-121).
    @State private var theme: ThemeSettingsModel
    /// The seasonal themes (LOT-166): Noël soft over the "Thème" settings, its window and its arrival.
    @State private var seasonal = SeasonalThemeModel(store: UserDefaultsSettingsStore())
    /// The optional Face ID / code lock, one for every scene (LOT-173).
    @State private var appLock = AppLockModel(store: UserDefaultsSettingsStore(), authenticator: LocalAuthenticationAuthenticator())
    /// The "Revenir à l'icône précédente ?" question once a seasonal icon's dates are over (#730).
    @State private var iconSeason = AppIconSeasonModel(store: UserDefaultsSettingsStore())
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let accounts = AccountsModel.live()
        _accounts = State(initialValue: accounts)
        _deletion = State(initialValue: AccountDeletionModel(accounts: accounts, eraser: .live))
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
                .environment(deletion)
                .environment(legacyImport)
                .environment(general)
                .environment(appLock)
                .environment(seasonal)
                .environment(\.avatarRefresh, avatarRefresh)
                // One type scale and one list density for every screen, live (LOT-169).
                .appTypography(general.textScale, density: general.listDensity)
                .appTheme(theme, seasonal: seasonal.activeTheme)
                // Snow over the screens, under the lock; the arrival alert waits until nothing covers them (LOT-166).
                .seasonalDecorations(seasonal, isCovered: { appLock.isCovered })
                // Over everything the scene shows, sheets included, while locked or in the app switcher (LOT-173).
                .appLockCover(appLock)
                .appIconSeasonAlert(iconSeason)
                // The legacy import first (LOT-158), so the accounts it takes over are in the store; then what iCloud Keychain
                // brought (LOT-173: a new device imports its accounts there); then the stored accounts and their sessions, once
                // per launch (LOT-081).
                .task {
                    await legacyImport.runAtLaunch()
                    accounts.reconcileAccountSync()
                    await accounts.restore()
                }
                // An account became current (restore, login, switch): the import goes on with it until complete (LOT-067 D3),
                // and the account list is read again when it took accounts over.
                .onChange(of: accounts.current?.id) { _, account in
                    Task {
                        if await legacyImport.accountDidChange(to: account) { await accounts.readStoreAgain() }
                    }
                }
                // The LOT-066 eviction policies, which nothing else runs: the offline pages' 200 MB budget (LOT-139).
                .task(priority: .utility) { await LiveOfflineStore().evict() }
                // Back in the foreground: sessions the forum did not confirm are checked again, quietly (#300).
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task {
                        // What another device changed first, so the re-check sees the current accounts (LOT-173).
                        accounts.reconcileAccountSync()
                        await accounts.recheckUnconfirmedSessions()
                    }
                }
                // The app lock follows the app's phase; it asks by itself once per lock (LOT-173).
                .onChange(of: scenePhase, initial: true) { _, phase in
                    if appLock.scenePhaseChanged(to: phase) { Task { await appLock.unlock() } }
                    // "First launch" of a season is the first activation on or after its date (THEMES.md §5).
                    if phase == .active { seasonal.sceneDidBecomeActive() }
                    // Crossing objects wait for foreground time only (THEMES.md §4 rule 4).
                    seasonal.crossings.foregroundChanged(active: phase == .active)
                }
        }
    }
}
