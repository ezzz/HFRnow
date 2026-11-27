import Foundation
import HFRClient
import HFRModels
import HFRNetwork
import HFRStorage
@testable import SwiftHFR
import Testing

/// The AQ feed read once per launch (#1398): a rebuilt root counts from it, roots built together share one read, and a launch read
/// that ends late never replaces a newer feed.
@MainActor
struct QualityAlertsLaunchFeedTests {
    typealias Support = QualityAlertsTestSupport

    /// #1398: a root rebuilt in the same process (an account switch, a login, a logout, another window) counts from the feed the
    /// first root read, at once: one request per launch, as legacy (`MainWindow.swift:1609` @ 87fe0d1c).
    @Test func aRebuiltRootCountsFromTheFeedAlreadyReadWithoutAskingAgain() async throws {
        let source = FakeQualityAlertsSource(items: try Support.capturedItems())
        let launchFeed = QualityAlertsLaunchFeed()
        let first = Support.model(source: source, launchFeed: launchFeed)
        await first.checkAtLaunch(sleep: { _ in })
        let waited = LaunchWaits()
        let rebuilt = Support.model(source: source, launchFeed: launchFeed)
        await rebuilt.checkAtLaunch(after: .seconds(3), sleep: { await waited.record($0) })
        #expect(source.calls == 1)
        #expect(rebuilt.unreadCount == 25)
        #expect(await waited.durations.isEmpty)
    }

    /// The app's wiring: `make` hands every environment the app's memo, and the roots built from one environment count from one
    /// read; an environment without a memo (built by hand) gives each root its own.
    @Test func rootsOfTheAppsEnvironmentShareTheFeedAndHandBuiltOnesDoNot() async throws {
        let items = try Support.capturedItems()
        var environment = AppEnvironment.make(session: HFRSession(), accountName: nil)
        #expect(environment.qualityAlertsFeed === QualityAlertsLaunchFeed.shared)

        let shared = FakeQualityAlertsSource(items: items)
        environment.qualityAlertsSource = shared
        // A memo of this test's own stands for `.shared`, which the rest of the test process must not inherit.
        environment.qualityAlertsFeed = QualityAlertsLaunchFeed()
        for _ in 0..<2 {
            await RootModel(environment: environment, store: InMemorySettingsStore()).qualityAlerts.checkAtLaunch(sleep: { _ in })
        }
        #expect(shared.calls == 1)

        let separate = FakeQualityAlertsSource(items: items)
        environment.qualityAlertsSource = separate
        environment.qualityAlertsFeed = nil
        for _ in 0..<2 {
            await RootModel(environment: environment, store: InMemorySettingsStore()).qualityAlerts.checkAtLaunch(sleep: { _ in })
        }
        #expect(separate.calls == 2)
    }

    /// Two windows built together share the one read in flight; a failed read is not kept, so the next root asks again.
    @Test func rootsBuiltTogetherShareOneReadAndAFailedReadIsNotKept() async throws {
        let items = try Support.capturedItems()
        let release = AQGate()
        let source = FakeQualityAlertsSource { index async throws(AQError) in
            if index == 0 { throw .network(.offline) }
            await release.wait()
            return items
        }
        let launchFeed = QualityAlertsLaunchFeed()
        await Support.model(source: source, launchFeed: launchFeed).checkAtLaunch(sleep: { _ in })
        #expect(source.calls == 1)
        let first = Support.model(source: source, launchFeed: launchFeed)
        let second = Support.model(source: source, launchFeed: launchFeed)
        async let checkFirst: Void = first.checkAtLaunch(sleep: { _ in })
        async let checkSecond: Void = second.checkAtLaunch(sleep: { _ in })
        await release.open()
        _ = await (checkFirst, checkSecond)
        #expect(source.calls == 2)
        #expect(first.unreadCount == 25 && second.unreadCount == 25)
    }

    /// A launch read still running when the list is loaded must not replace the newer feed of the load in the memo.
    @Test func aLaunchReadEndingAfterALoadKeepsTheLoadedFeed() async throws {
        let items = try Support.capturedItems()
        let older = Array(items.prefix(3))
        let release = AQGate()
        let source = FakeQualityAlertsSource { index async throws(AQError) in
            guard index == 0 else { return items }
            await release.wait()
            return older
        }
        let launchFeed = QualityAlertsLaunchFeed()
        let model = Support.model(source: source, launchFeed: launchFeed)
        let launch = Task { await model.checkAtLaunch(sleep: { _ in }) }
        while source.calls == 0 { await Task.yield() }
        await model.load()
        await release.open()
        await launch.value
        #expect(launchFeed.items?.count == items.count)
    }
}

private actor LaunchWaits {
    private(set) var durations: [Duration] = []
    func record(_ duration: Duration) { durations.append(duration) }
}
