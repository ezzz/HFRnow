import Foundation
import HFRClient
import HFRModels
import HFRNetwork
import HFRParsing
import HFRStorage
@testable import SwiftHFR
import SwiftUI
import Testing

/// The Alertes Qualitay model over the captured feed `T01` (LOT-133).
@MainActor
struct QualityAlertsModelTests {
    typealias Support = QualityAlertsTestSupport

    @Test func theCountAtLaunchIsEveryItemWhenNothingWasChecked() async throws {
        let source = FakeQualityAlertsSource(items: try Support.capturedItems())
        let model = Support.model(source: source)
        #expect(model.unreadCount == 0)
        await model.checkAtLaunch(sleep: { _ in })
        // Logged out and never checked: the 25 items of `T01`, as legacy shows "25" on a first launch.
        #expect(model.unreadCount == 25)
        #expect(source.calls == 1)
    }

    @Test func theCountOnlyHoldsItemsNewerThanTheLastCheck() async throws {
        let store = InMemorySettingsStore()
        store.set(Support.lastCheckOfTheOracle, for: SettingKey.aqLastCheck)
        let model = Support.model(source: FakeQualityAlertsSource(items: try Support.capturedItems()), store: store)
        await model.refreshCount()
        #expect(model.unreadCount == 2)
        // The count does not mark anything as seen.
        #expect(store.value(for: SettingKey.aqLastCheck) == Support.lastCheckOfTheOracle)
    }

    @Test func showingTheListMarksItSeenAndClearsTheBadge() async throws {
        let store = InMemorySettingsStore()
        store.set(Support.lastCheckOfTheOracle, for: SettingKey.aqLastCheck)
        let model = Support.model(source: FakeQualityAlertsSource(items: try Support.capturedItems()), store: store)
        await model.refreshCount()
        #expect(model.unreadCount == 2)
        await model.load()
        #expect(model.rows.count == 25)
        // The rows keep what was new before this visit.
        #expect(model.rows.filter(\.isNew).count == 2)
        // #1160: the state is spoken, not only drawn as weight; a seen row says nothing and is regular.
        #expect(model.rows.filter { $0.accessibilityState == "Nouvelle" }.count == 2)
        #expect(model.rows.allSatisfy { $0.isNew == ($0.accessibilityState == "Nouvelle") })
        let new = try #require(model.rows.first(where: { $0.isNew }))
        let seen = try #require(model.rows.first(where: { !$0.isNew }))
        #expect(new.titleStyle == .headline && seen.titleStyle == .body)
        #expect(model.unreadCount == 0)
        #expect(store.value(for: SettingKey.aqLastCheck) == Support.shownAt)
        // Next launch: nothing is newer than that visit.
        await model.refreshCount()
        #expect(model.unreadCount == 0)
        #expect(model.hasLoaded && model.failure == nil && !model.isLoading)
    }

    @Test func aCountThatStartedBeforeTheListWasShownCannotBringTheBadgeBack() async throws {
        let items = try Support.capturedItems()
        let entered = AQGate()
        let release = AQGate()
        let source = FakeQualityAlertsSource { (call: Int) async throws(AQError) -> [AQFeedItem] in
            if call == 0 {
                await entered.open()
                await release.wait()
            }
            return items
        }
        let model = Support.model(source: source)
        let count = Task { await model.refreshCount() }
        await entered.wait()
        await model.load()
        await release.open()
        await count.value
        #expect(model.unreadCount == 0)
    }

    @Test func aCountThatStartsWhileTheListLoadsCannotBringTheBadgeBack() async throws {
        let items = try Support.capturedItems()
        let loadEntered = AQGate()
        let loadRelease = AQGate()
        let countEntered = AQGate()
        let countRelease = AQGate()
        let source = FakeQualityAlertsSource { (call: Int) async throws(AQError) -> [AQFeedItem] in
            if call == 0 {
                await loadEntered.open()
                await loadRelease.wait()
            } else {
                await countEntered.open()
                await countRelease.wait()
            }
            return items
        }
        let model = Support.model(source: source)
        let load = Task { await model.load() }
        await loadEntered.wait()
        // The launch check fires while the list loads: it reads the last check from before the visit.
        let count = Task { await model.refreshCount() }
        await countEntered.wait()
        await loadRelease.open()
        await load.value
        #expect(model.unreadCount == 0)
        await countRelease.open()
        await count.value
        #expect(model.unreadCount == 0)
    }

    @Test func aFailedCountKeepsTheBadgeAndAFailedLoadKeepsTheRowsAndMarksNothing() async throws {
        let items = try Support.capturedItems()
        let store = InMemorySettingsStore()
        let source = FakeQualityAlertsSource { (call: Int) async throws(AQError) -> [AQFeedItem] in
            if call < 2 { return items }
            throw .network(.offline)
        }
        let model = Support.model(source: source, store: store)
        await model.refreshCount()
        #expect(model.unreadCount == 25)
        await model.load()
        let seenAt = store.value(for: SettingKey.aqLastCheck)
        #expect(seenAt == Support.shownAt)
        // Offline now: the rows stay, the failure shows, the last check does not move.
        await model.load()
        #expect(model.rows.count == 25)
        #expect(model.failure == .offline)
        #expect(store.value(for: SettingKey.aqLastCheck) == seenAt)
        #expect(!model.isLoading)
        await model.refreshCount()
        #expect(model.unreadCount == 0)
    }

    @Test func aFailedCountAtLaunchSaysNothing() async {
        let source = FakeQualityAlertsSource { _ async throws(AQError) in throw .http(statusCode: 503) }
        let model = Support.model(source: source)
        await model.checkAtLaunch(sleep: { _ in })
        #expect(model.unreadCount == 0)
        #expect(model.failure == nil)
    }

    @Test func aCancelledFirstLoadIsNeitherAFailureNorAnEmptyList() async throws {
        let items = try Support.capturedItems()
        let store = InMemorySettingsStore()
        let entered = AQGate()
        let release = AQGate()
        let source = FakeQualityAlertsSource { (call: Int) async throws(AQError) -> [AQFeedItem] in
            if call == 0 {
                await entered.open()
                await release.wait()
                throw .network(.cancelled)
            }
            return items
        }
        let model = Support.model(source: source, store: store)
        let visit = Task { await model.load() }
        await entered.wait()
        visit.cancel()
        await release.open()
        await visit.value
        #expect(source.calls == 1) // a cancellation that was asked for is not asked again
        // A tab switch cancelled it: nothing was learned, so the screen still shows its spinner state and nothing is marked seen.
        #expect(!model.hasLoaded && !model.isLoading)
        #expect(model.failure == nil && model.rows.isEmpty)
        #expect(store.value(for: SettingKey.aqLastCheck) == nil)
        // Asking again works.
        await model.load()
        #expect(model.hasLoaded && model.rows.count == 25)
    }

    /// The transport answered `.cancelled` while nothing cancelled the visit (#1191): it is asked once more.
    @Test func aCancellationNobodyAskedForIsRetriedOnce() async throws {
        let items = try Support.capturedItems()
        let source = FakeQualityAlertsSource { (call: Int) async throws(AQError) -> [AQFeedItem] in
            if call == 0 { throw .network(.cancelled) }
            return items
        }
        let model = Support.model(source: source)
        await model.load()
        #expect(source.calls == 2)
        #expect(model.hasLoaded && model.failure == nil && model.rows.count == 25)
    }

    /// Twice: a failure with "Réessayer", never "Chargement…" for ever (#1191).
    @Test func aCancellationNobodyAskedForEndsTheLoad() async {
        let store = InMemorySettingsStore()
        let source = FakeQualityAlertsSource { _ async throws(AQError) in throw .network(.cancelled) }
        let model = Support.model(source: source, store: store)
        await model.load()
        #expect(source.calls == 2)
        #expect(model.hasLoaded && model.failure == .other && !model.isLoading)
        #expect(store.value(for: SettingKey.aqLastCheck) == nil)
    }

    @Test func aFailedFirstLoadIsAFailureNotAnEmptyList() async {
        let source = FakeQualityAlertsSource { _ async throws(AQError) in throw .invalidResponse(.malformedDocument) }
        let store = InMemorySettingsStore()
        let model = Support.model(source: source, store: store)
        await model.load()
        #expect(model.rows.isEmpty)
        #expect(model.failure == .other)
        #expect(model.hasLoaded)
        #expect(store.value(for: SettingKey.aqLastCheck) == nil)
    }

    @Test func aBuildWithoutAnAQAddressIsUnavailableAndSendsNothing() async {
        let model = Support.model(source: nil)
        await model.load()
        await model.checkAtLaunch(sleep: { _ in })
        #expect(model.failure == .unavailable)
        #expect(model.rows.isEmpty && model.unreadCount == 0)
    }

    @Test func theLaunchCheckWaitsThenFetchesAndACancelledWaitFetchesNothing() async throws {
        let source = FakeQualityAlertsSource(items: try Support.capturedItems())
        let model = Support.model(source: source)
        let waited = Waited()
        await model.checkAtLaunch(after: .seconds(3), sleep: { await waited.record($0) })
        #expect(await waited.durations == [.seconds(3)])
        #expect(source.calls == 1)

        let cancelled = Support.model(source: source)
        await cancelled.checkAtLaunch(sleep: { _ in throw CancellationError() })
        #expect(source.calls == 1)
        #expect(cancelled.unreadCount == 0)
    }

    /// #1398: a root rebuilt in the same process (an account switch, a login, a logout, another window) counts from the feed the
    /// first root read, at once: one request per launch, as legacy (`MainWindow.swift:1609` @ 87fe0d1c).
    @Test func aRebuiltRootCountsFromTheFeedAlreadyReadWithoutAskingAgain() async throws {
        let source = FakeQualityAlertsSource(items: try Support.capturedItems())
        let launchFeed = QualityAlertsLaunchFeed()
        let first = Support.model(source: source, launchFeed: launchFeed)
        await first.checkAtLaunch(sleep: { _ in })
        let waited = Waited()
        let rebuilt = Support.model(source: source, launchFeed: launchFeed)
        await rebuilt.checkAtLaunch(after: .seconds(3), sleep: { await waited.record($0) })
        #expect(source.calls == 1)
        #expect(rebuilt.unreadCount == 25)
        #expect(await waited.durations.isEmpty)
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

    @Test func aNewerLoadWinsOverAnOlderOneStillRunning() async throws {
        let items = try Support.capturedItems()
        let entered = AQGate()
        let release = AQGate()
        let source = FakeQualityAlertsSource { (call: Int) async throws(AQError) -> [AQFeedItem] in
            if call == 0 {
                await entered.open()
                await release.wait()
                return Array(items.prefix(3))
            }
            return items
        }
        let model = Support.model(source: source)
        let first = Task { await model.load() }
        await entered.wait()
        await model.load()
        await release.open()
        await first.value
        #expect(model.rows.count == 25)
        #expect(!model.isLoading)
    }
}

/// Records the waits the launch check asked for.
private actor Waited {
    private(set) var durations: [Duration] = []
    func record(_ duration: Duration) { durations.append(duration) }
}
