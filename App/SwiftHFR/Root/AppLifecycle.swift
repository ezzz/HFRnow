import HFRNetwork
import SwiftUI

// Port: none @ 87fe0d1c (legacy's app delegate runs this work once; `HFRswiftApp.swift:25-35` @ 87fe0d1c attaches the scene phase
// handler to the `WindowGroup` scene). Differences: the handlers run from the content of every window, so they are functions of
// one object that act once however many windows call them (LOT-146, GAP-219).
/// What the app does once for all its windows: the launch sequence, and the reaction to a change of account or of scene phase.
///
/// The `App`'s content closures run once per window and the phase it reads is the aggregate of all windows, so every window
/// calls these functions for each change; only the first call of a change does the work.
@MainActor
final class AppLifecycle {
    /// The side effects, so a test counts and orders them without the models.
    struct Steps: Sendable {
        /// The legacy import of the launch (LOT-158).
        var importLegacy: @MainActor () async -> Void
        /// What iCloud Keychain brought, and what another device changed (LOT-173).
        var reconcileAccounts: @MainActor () -> Void
        /// The stored accounts and their sessions (LOT-081).
        var restoreAccounts: @MainActor () async -> Void
        /// An account became current: the import goes on with it (LOT-067 D3).
        var importForAccount: @MainActor (String?) async -> Void
        /// Back in the foreground: sessions the forum did not confirm are checked again (#300).
        var recheckSessions: @MainActor () async -> Void
        /// The next background MP check (LOT-140).
        var scheduleBackgroundCheck: @MainActor () async -> Void
        /// The offline pages' budget (LOT-139).
        var evictOffline: @MainActor () async -> Void
        /// The app lock and the seasons follow the phase (LOT-173, LOT-166).
        var lockAndSeasons: @MainActor (ScenePhase) -> Void
        /// An account became current: the notification prompt, in context rather than at launch (#1172).
        var askNotificationPermission: @MainActor (String?) async -> Void
    }

    private let events = AppWideEvents()
    private let steps: Steps
    private var launchTask: Task<Void, Never>?

    init(steps: Steps) {
        self.steps = steps
    }

    /// The launch sequence, import then reconcile then restore, once. A window that asks while it runs waits for the same run:
    /// reading the accounts before the import wrote them would hide what it took over until the next launch (LOT-158).
    func launch() async {
        if let launchTask { return await launchTask.value }
        let task = Task { [steps] in
            await steps.importLegacy()
            steps.reconcileAccounts()
            await steps.restoreAccounts()
        }
        launchTask = task
        await task.value
    }

    /// The offline budget, once per launch.
    func evictOfflineOnce() async {
        guard events.firstTime("offlineEviction") else { return }
        await steps.evictOffline()
    }

    /// The current account changed: the notification prompt, then the import goes on with it, once for the change. The prompt
    /// comes first: right after the login it answers, never later over the import's own summary.
    func currentAccountChanged(to account: String?) async {
        guard events.isNew(account, for: "currentAccount") else { return }
        await steps.askNotificationPermission(account)
        await steps.importForAccount(account)
    }

    /// The scene phase changed: re-check the sessions when active, schedule the background check when in the background.
    func scenePhaseChanged(to phase: ScenePhase) async {
        guard events.isNew(phase, for: "phase") else { return }
        switch phase {
        case .active: await steps.recheckSessions()
        case .background: await steps.scheduleBackgroundCheck()
        default: break
        }
    }

    /// The lock and the seasons follow the phase, with the phase a window starts on; a window opened while the app is active sees
    /// the active phase again, which is not a new activation.
    func lockAndSeasonsFollow(_ phase: ScenePhase) {
        guard events.isNew(phase, for: "lockAndSeasons") else { return }
        steps.lockAndSeasons(phase)
    }
}

extension AppLifecycle {
    /// The app's steps over its shared models.
    static func live(
        accounts: AccountsModel, legacyImport: LegacyImportModel, appLock: AppLockModel, seasonal: SeasonalThemeModel
    ) -> AppLifecycle {
        // DO NOT MERGE (#1276): one line at the start and end of each launch step.
        AppLifecycle(steps: Steps(
            importLegacy: {
                T1276.log("launch legacyImport.runAtLaunch start")
                await legacyImport.runAtLaunch()
                T1276.log("launch legacyImport.runAtLaunch end")
            },
            reconcileAccounts: {
                T1276.log("launch iCloud reconcileAccountSync start")
                accounts.reconcileAccountSync()
                T1276.log("launch iCloud reconcileAccountSync end")
            },
            restoreAccounts: {
                T1276.log("launch accounts.restore start")
                await accounts.restore()
                T1276.log("launch accounts.restore end")
            },
            importForAccount: { account in
                T1276.log("launch legacyImport.accountDidChange start hasAccount=\(account != nil)")
                if await legacyImport.accountDidChange(to: account) { await accounts.readStoreAgain() }
                T1276.log("launch legacyImport.accountDidChange end")
            },
            recheckSessions: {
                // What another device changed first, so the re-check sees the current accounts (LOT-173).
                T1276.log("active recheckSessions start")
                accounts.reconcileAccountSync()
                await accounts.recheckUnconfirmedSessions()
                T1276.log("active recheckSessions end")
            },
            scheduleBackgroundCheck: { await MPBackgroundScheduler.schedule() },
            evictOffline: { await LiveOfflineStore().evict() },
            lockAndSeasons: { phase in
                if appLock.scenePhaseChanged(to: phase) { Task { await appLock.unlock() } }
                // "First launch" of a season is the first activation on or after its date (THEMES.md §5).
                if phase == .active { seasonal.sceneDidBecomeActive() }
            },
            askNotificationPermission: { account in
                T1276.log("launch notificationPrompt start hasAccount=\(account != nil)")
                await MPNotificationPrompt.live.accountBecameCurrent(account)
                T1276.log("launch notificationPrompt end")
            }
        ))
    }
}
