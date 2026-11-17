import Foundation
import HFRNetwork
import HFRStorage
import Observation
import SwiftUI
@testable import SwiftHFR
import Testing

/// LOT-146: several windows of the app. Each window builds its own root; the models behind them are shared.
@MainActor
struct MultiWindowTests {
    // Xcode 27.2 writes `UIApplicationSupportsMultipleScenes` = true into the generated scene manifest by itself, and an
    // `INFOPLIST_KEY_UIApplicationSupportsMultipleScenes` or a manifest in `Info-Keys.plist` does not change it (measured, LOT-146):
    // nothing in the project sets it, so this guards the built bundle against a toolchain or a manifest change.
    @Test func theBundleDeclaresMultipleScenes() throws {
        let manifest = try #require(Bundle.main.infoDictionary?["UIApplicationSceneManifest"] as? [String: Any])
        #expect(manifest["UIApplicationSupportsMultipleScenes"] as? Bool == true)
    }

    // The scene phase the App reads is one value for every window: a handler in each window's content sees each change once per
    // window, and only the first may act.
    @Test func aChangeSeenByEveryWindowIsNewOnlyTheFirstTime() {
        let events = AppWideEvents()
        #expect(events.isNew(ScenePhase.active, for: "recheck"))
        #expect(!events.isNew(ScenePhase.active, for: "recheck"))
        #expect(events.isNew(ScenePhase.background, for: "recheck"))
        // Back to active is a new change, not the one before.
        #expect(events.isNew(ScenePhase.active, for: "recheck"))
        // Another handler keeps its own record.
        #expect(events.isNew(ScenePhase.active, for: "schedule"))
    }

    @Test func launchWorkRunsOncePerProcess() {
        let events = AppWideEvents()
        #expect(events.firstTime("offlineEviction"))
        #expect(!events.firstTime("offlineEviction"))
        #expect(!events.firstTime("offlineEviction"))
        #expect(events.firstTime("other"))
    }

    @Test func theCurrentAccountChangeIsHandledOnceWhateverTheNumberOfWindows() {
        let events = AppWideEvents()
        let handled = (0..<3).filter { _ in events.isNew("account-a" as String?, for: "currentAccount") }.count
        #expect(handled == 1)
        #expect(events.isNew(nil as String?, for: "currentAccount"))
    }

    // Findings of review round 1: the guards are tested where the app uses them, through `AppLifecycle` and the router.
    @Test func twoWindowsLaunchingAtOnceRunTheSequenceOnceAndBothWaitForIt() async {
        let log = Log()
        let lifecycle = AppLifecycle(steps: log.steps(importYields: 20))
        let first = Task { await lifecycle.launch() }
        let second = Task {
            await lifecycle.launch()
            log.add("second-returned")
        }
        await first.value
        await second.value
        // The second window did not return, and did not read the accounts, before the import had written them.
        #expect(log.entries == ["import-start", "import-end", "reconcile", "restore", "second-returned"])
    }

    @Test func aWindowOpenedAfterTheLaunchDoesNotRunItAgain() async {
        let log = Log()
        let lifecycle = AppLifecycle(steps: log.steps())
        await lifecycle.launch()
        await lifecycle.launch()
        #expect(log.entries.filter { $0 == "restore" }.count == 1)
    }

    @Test func everyWindowSeeingAChangeRunsItsReactionOnce() async {
        let log = Log()
        let lifecycle = AppLifecycle(steps: log.steps())
        for _ in 0..<2 { await lifecycle.currentAccountChanged(to: "a") }
        for _ in 0..<2 { await lifecycle.scenePhaseChanged(to: .active) }
        for _ in 0..<2 { await lifecycle.scenePhaseChanged(to: .background) }
        await lifecycle.scenePhaseChanged(to: .active)
        for _ in 0..<2 { await lifecycle.evictOfflineOnce() }
        for _ in 0..<2 { lifecycle.lockAndSeasonsFollow(.active) }
        #expect(log.entries.filter { $0 == "importForAccount" }.count == 1)
        #expect(log.entries.filter { $0 == "recheck" }.count == 2)
        #expect(log.entries.filter { $0 == "schedule" }.count == 1)
        #expect(log.entries.filter { $0 == "evict" }.count == 1)
        #expect(log.entries.filter { $0 == "lock" }.count == 1)
    }

    @Test func aTapStaysInTheRouterUntilAWindowIsActive() {
        let router = MPNotificationRouter()
        router.receive(.thread(7))
        #expect(RootNavigationView.takeNotification(phase: .background, from: router) == nil)
        #expect(RootNavigationView.takeNotification(phase: .inactive, from: router) == nil)
        #expect(router.pending == .thread(7))
        #expect(RootNavigationView.takeNotification(phase: .active, from: router) == .thread(7))
        #expect(RootNavigationView.takeNotification(phase: .active, from: router) == nil)
    }

    @Test func onlyTheFirstWindowPresentsWhatASharedModelRaisesAndTheNextOneTakesOverWhenItCloses() {
        let claims = SceneClaims()
        let (one, two) = (UUID(), UUID())
        claims.claim("iconSeason", scene: one)
        claims.claim("iconSeason", scene: two)
        #expect(claims.isPresenting("iconSeason", scene: one))
        #expect(!claims.isPresenting("iconSeason", scene: two))
        // Another thing is claimed on its own.
        claims.claim("legacyImportSummary", scene: two)
        #expect(claims.isPresenting("legacyImportSummary", scene: two))
        claims.release(scene: one)
        claims.claim("iconSeason", scene: two)
        #expect(claims.isPresenting("iconSeason", scene: two))
    }

    // Review round 2: a window that is away does not keep what it presents.
    @Test func aWindowGoingToTheBackgroundHandsWhatItPresentsToOneOnScreen() {
        let claims = SceneClaims()
        let (one, two) = (UUID(), UUID())
        claims.phaseChanged(.active, scene: one, key: "legacyImportSummary")
        claims.phaseChanged(.active, scene: two, key: "legacyImportSummary")
        #expect(claims.isPresenting("legacyImportSummary", scene: one))
        // An inactive window (a system sheet over it) keeps its claim; a background one gives it up.
        claims.phaseChanged(.inactive, scene: one, key: "legacyImportSummary")
        #expect(claims.isPresenting("legacyImportSummary", scene: one))
        claims.phaseChanged(.background, scene: one, key: "legacyImportSummary")
        #expect(!claims.isPresenting("legacyImportSummary", scene: one))
        claims.phaseChanged(.active, scene: two, key: "legacyImportSummary")
        #expect(claims.isPresenting("legacyImportSummary", scene: two))
        // Coming back does not take it from the window that presents it.
        claims.phaseChanged(.active, scene: one, key: "legacyImportSummary")
        #expect(!claims.isPresenting("legacyImportSummary", scene: one))
    }

    @Test func aNotificationTapWaitsForAWindowOnScreen() {
        #expect(RootNavigationView.mayOpenNotification(phase: .active))
        #expect(!RootNavigationView.mayOpenNotification(phase: .inactive))
        #expect(!RootNavigationView.mayOpenNotification(phase: .background))
    }

    @Test func windowsOfOneSessionShareTheMessagesCountAndANewSessionStartsAnother() {
        let counts = SharedPrivateMessageCounts()
        let first = counts.count(forGeneration: 1)
        #expect(counts.count(forGeneration: 1) === first)
        let next = counts.count(forGeneration: 2)
        #expect(next !== first)
        #expect(counts.count(forGeneration: 2) === next)
    }

    // Two roots built as two windows build them: from one environment of the app. The navigation is each window's; the count
    // and the settings are the app's.
    @Test func twoRootsShareTheAppsStateAndNotTheirNavigation() {
        let counts = SharedPrivateMessageCounts()
        let count = counts.count(forGeneration: 1)
        let store = InMemorySettingsStore()
        let session = HFRSession()
        let one = RootModel(
            environment: AppEnvironment.make(session: session, accountName: nil, privateMessageCount: count), store: store
        )
        let two = RootModel(
            environment: AppEnvironment.make(session: session, accountName: nil, privateMessageCount: count), store: store
        )
        one.selectedDestination = .tab(.messages)
        #expect(two.selectedDestination != .tab(.messages))
        #expect(one.categories !== two.categories)
        #expect(one.messages !== two.messages)
        #expect(one.favorites !== two.favorites)
        // A count a list page of one window announced is on the badge of the other.
        count.record(4, ticket: count.ticket())
        #expect(one.unreadPrivateMessages == 4)
        #expect(two.unreadPrivateMessages == 4)
        // A setting changed in one window follows in the other.
        store.set(false, for: SettingKey.privateMessageBadge)
        one.reloadSettings()
        two.reloadSettings()
        #expect(one.unreadPrivateMessages == 0)
        #expect(two.unreadPrivateMessages == 0)
    }

    // A window opened while the dated-icon question is on screen in another one must leave it alone: the check at launch clears
    // the question first, which would dismiss the alert under the user's finger.
    @Test func aSecondWindowDoesNotResetTheIconQuestionTheFirstShows() {
        let calendar = IconTestCalendar.calendar
        let store = InMemorySettingsStore(["icon": .string("noel-hfr"), "icon_previous": .string("blue")])
        let model = AppIconSeasonModel(
            store: store, switcher: FakeIconSwitcher(current: "Icon-NOEL-HFR"), calendar: calendar,
            now: { IconTestCalendar.date(2026, 12, 27) }
        )
        model.checkOnceAtLaunch()
        #expect(model.question != nil)
        let touched = Touched()
        withObservationTracking { _ = model.question } onChange: { touched.set() }
        model.checkOnceAtLaunch()
        #expect(!touched.value)
        #expect(model.question?.dated == .noelHfr)
    }
}

/// A flag the observation callback sets (it is `@Sendable`).
private final class Touched: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false

    var value: Bool { lock.withLock { flag } }

    func set() { lock.withLock { flag = true } }
}

/// Records the steps of an `AppLifecycle`.
@MainActor
private final class Log {
    private(set) var entries: [String] = []

    func add(_ entry: String) { entries.append(entry) }

    func steps(importYields: Int = 0) -> AppLifecycle.Steps {
        AppLifecycle.Steps(
            importLegacy: {
                self.add("import-start")
                for _ in 0..<importYields { await Task.yield() }
                self.add("import-end")
            },
            reconcileAccounts: { self.add("reconcile") },
            restoreAccounts: { self.add("restore") },
            importForAccount: { _ in self.add("importForAccount") },
            recheckSessions: { self.add("recheck") },
            scheduleBackgroundCheck: { self.add("schedule") },
            evictOffline: { self.add("evict") },
            lockAndSeasons: { _ in self.add("lock") }
        )
    }
}
