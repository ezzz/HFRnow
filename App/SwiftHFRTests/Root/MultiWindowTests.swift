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
