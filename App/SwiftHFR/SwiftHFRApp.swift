import HFRStorage
import SwiftUI

// Port of HFRswift/Swift/HFRswiftApp.swift (HFRswiftApp) @ 87fe0d1c (`:12-37`; the manifest `Info.plist:204-208` @ 2fe43da3).
// Differences: no ObjC app delegate; HFRKit is the engine. Several windows (iPad, `UIApplicationSupportsMultipleScenes`, as legacy
// since `afec5433`): every window starts a fresh root, and the models below are created once here, so all windows share them;
// what the content closures run once per process or per change goes through `AppWideEvents`, as legacy's launch work ran once in
// the app delegate (LOT-146, GAP-219).
// The background MP check (LOT-140) is SwiftUI's `.backgroundTask(.appRefresh)` instead of `BGTaskScheduler.register` (87fe0d1c
// `HFRswiftApp.swift:21`, `MPBackgroundService.swift:21-31`).
/// Entry point of the SwiftHFR iOS app; the composition root for every screen.
@main
struct SwiftHFRApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var accounts: AccountsModel
    /// The deletion screen's wipe (LOT-157), app-wide: erasing the current account rebuilds the root navigation.
    @State private var deletion: AccountDeletionModel
    /// The legacy import (LOT-158): at launch before the accounts are read, then at each change of the current account.
    @State private var legacyImport: LegacyImportModel
    /// Bumped when the avatar cache gets a file, so MP rows read it again (GAP-227).
    @State private var avatarRefresh = AvatarRefresh()
    /// The "Général" settings, shared by the settings screen and every screen that reads the type scale and density.
    @State private var general: GeneralSettingsModel
    /// The "Thème" settings: appearance and colours of every screen and of the reader (LOT-121).
    @State private var theme: ThemeSettingsModel
    /// The seasonal themes (LOT-166): Noël soft over the "Thème" settings, its window and its arrival.
    @State private var seasonal: SeasonalThemeModel
    /// The optional Face ID / code lock, one for every scene (LOT-173).
    @State private var appLock: AppLockModel
    /// The "Revenir à l'icône précédente ?" question once a seasonal icon's dates are over (#730).
    @State private var iconSeason = AppIconSeasonModel(store: UserDefaultsSettingsStore())
    /// The Réglages › Expérimental switches (#903), read by the screens whose modern path they gate. Created in `init`, after the
    /// launch migration: a property initialiser would read `experimental.mpDarkTopic` before the migration writes it (#1014).
    @State private var experimental: ExperimentalSettings
    /// What runs once for the whole app, not once per window (LOT-146).
    @State private var lifecycle: AppLifecycle
    /// Which window presents what the shared models raise (the icon question, the import summary), one window each (LOT-146).
    @State private var sceneClaims = SceneClaims()
    /// The Messages badge count of the current session, one for every window (LOT-146).
    @State private var messageCounts = SharedPrivateMessageCounts()
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
        _experimental = State(initialValue: ExperimentalSettings(store: UserDefaultsSettingsStore()))
        let legacyImport = LegacyImportModel(importer: LegacyImportServices.liveImporter)
        let seasonal = SeasonalThemeModel(store: UserDefaultsSettingsStore())
        let appLock = AppLockModel(store: UserDefaultsSettingsStore(), authenticator: LocalAuthenticationAuthenticator())
        _legacyImport = State(initialValue: legacyImport)
        _seasonal = State(initialValue: seasonal)
        _appLock = State(initialValue: appLock)
        _lifecycle = State(initialValue: AppLifecycle.live(
            accounts: accounts, legacyImport: legacyImport, appLock: appLock, seasonal: seasonal
        ))
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
                .environment(experimental)
                .environment(\.avatarRefresh, avatarRefresh)
                .environment(\.sharedPrivateMessageCounts, messageCounts)
                .environment(\.sceneClaims, sceneClaims)
                // One type scale and one list density for every screen, live (LOT-169).
                .appTypography(general.textScale, density: general.listDensity)
                .appTheme(theme, seasonal: seasonal.drawnTheme)
                // Snow over the screens, under the lock; the arrival alert waits until nothing covers them (LOT-166).
                .seasonalDecorations(seasonal, isCovered: { appLock.isCovered })
                // Over everything the scene shows, sheets included, while locked or in the app switcher (LOT-173).
                .appLockCover(appLock)
                .appIconSeasonAlert(iconSeason)
                // The legacy import first (LOT-158), so the accounts it takes over are in the store; then what iCloud Keychain
                // brought (LOT-173: a new device imports its accounts there); then the stored accounts and their sessions, once
                // per launch (LOT-081): every window asks, the sequence runs once and all of them wait for it (`AppLifecycle`).
                .task { await lifecycle.launch() }
                // An account became current (restore, login, switch): the import goes on with it until complete (LOT-067 D3),
                // and the account list is read again when it took accounts over.
                .onChange(of: accounts.current?.id) { _, account in
                    Task { await lifecycle.currentAccountChanged(to: account) }
                }
                // The LOT-066 eviction policies, which nothing else runs: the offline pages' 200 MB budget (LOT-139).
                .task(priority: .utility) { await lifecycle.evictOfflineOnce() }
                // Back in the foreground: sessions the forum did not confirm are checked again, quietly (#300); the next background
                // MP check is scheduled when the app leaves the screen (`HFRswiftApp.swift:31-35`). The phase the App reads is the
                // aggregate of every window.
                .onChange(of: scenePhase) { _, phase in
                    Task { await lifecycle.scenePhaseChanged(to: phase) }
                }
                // Notification permission at launch, as legacy (`HFRswiftApp.swift:27-29` @ 87fe0d1c, LOT-140); iOS asks once.
                .task { await MPNotificationCenter().prepare() }
                // The app lock follows the app's phase; it asks by itself once per lock (LOT-173).
                .onChange(of: scenePhase, initial: true) { _, phase in lifecycle.lockAndSeasonsFollow(phase) }
        }
        // The background MP check (LOT-140): the next one is scheduled first, as legacy (`MPBackgroundService.swift:71`).
        .backgroundTask(.appRefresh(MPBackgroundScheduler.taskIdentifier)) {
            await MPBackgroundScheduler.schedule()
            await MPBackgroundCheck.live.run()
        }
    }
}
