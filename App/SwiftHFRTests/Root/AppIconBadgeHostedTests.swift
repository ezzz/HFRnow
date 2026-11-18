import HFRModels
import HFRNetwork
import HFRStorage
import Observation
@testable import SwiftHFR
import SwiftUI
import Testing
import UIKit

/// #1060: the app icon badge of the real root, hosted as the app builds it, with the Messages tab never opened.
@MainActor
@Suite(.serialized)
struct AppIconBadgeHostedTests {
    /// The scene phase the hosted root reads, so a test can take the window away and back.
    @MainActor
    @Observable
    final class Phase {
        var value: ScenePhase = .active
    }

    private struct Host: View {
        let environment: AppEnvironment
        let store: any SettingsStore
        let badges: any MPNotificationDelivering
        let phase: Phase

        var body: some View {
            RootNavigationView(environment: environment, store: store, badges: badges)
                .environment(\.scenePhase, phase.value)
        }
    }

    /// An environment of the logged-out session whose lists come from `source`, sharing `count` as the app's windows do.
    private func environment(_ source: FakeDataSource, count: PrivateMessageCount) -> AppEnvironment {
        let live = AppEnvironment.make(session: HFRSession(), accountName: nil, privateMessageCount: count)
        return AppEnvironment(
            session: live.session, dataSource: source, visibility: live.visibility, currentAccountName: nil,
            topicPages: FakeTopicPages(), reader: live.reader, privateMessages: FakePrivateMessages(), composer: nil,
            filteredPosts: live.filteredPosts, favoriteStores: live.favoriteStores, flagActions: nil, memberAvatars: nil,
            pseudoListsSnapshot: live.pseudoListsSnapshot, blocklistChanges: nil, privateMessageCount: count
        )
    }

    private func host(_ view: some View) throws -> UIWindow {
        let accounts = makeModel(store: InMemoryCredentialStore())
        let controller = UIHostingController(rootView: view.environment(accounts))
        let scene = try #require(UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = controller
        window.isHidden = false
        controller.view.layoutIfNeeded()
        return window
    }

    /// Waits up to 2 s for `condition`.
    private func wait(until condition: () async -> Bool) async throws {
        for _ in 0..<100 where !(await condition()) {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    // The home page the root loads at launch, whatever the start tab, carries the count: the badge follows it with Messages
    // never opened (legacy reads `nb_mp` from the home page, `ObjCForumsParser.m:516-525` @ 87fe0d1c).
    @Test func theLaunchsHomePageGivesTheIconItsCountWithoutOpeningMessages() async throws {
        let source = FakeDataSource()
        source.forumHandler = { ForumListPage(forums: [], isLoggedIn: true, unreadPrivateMessages: 3) }
        let count = PrivateMessageCount()
        let delivery = FakeMPDelivery()
        let store = InMemorySettingsStore()
        let window = try host(Host(environment: environment(source, count: count), store: store, badges: delivery, phase: Phase()))
        defer { window.isHidden = true }
        try await wait { await delivery.badges.contains(3) }
        #expect(source.requests.contains("forums"))
        #expect(!source.requests.contains { $0.contains("prive") })
        #expect(count.latest == 3)
        #expect(await delivery.badges == [3])
    }

    // #1060: the first launch's count can come while iOS's permission prompt is on screen, so iOS drops the badge; legacy sets
    // it again each time the app is back on screen (`MainWindow.swift:2588-2593` @ 87fe0d1c), the prompt's answer included.
    @Test func aBadgeIOSDidNotShowIsSetAgainWhenTheWindowIsBackOnScreen() async throws {
        let source = FakeDataSource()
        source.forumHandler = { ForumListPage(forums: [], isLoggedIn: true, unreadPrivateMessages: 3) }
        let delivery = FakeMPDelivery(badgeAllowed: false)
        let phase = Phase()
        phase.value = .inactive
        let view = Host(
            environment: environment(source, count: PrivateMessageCount()), store: InMemorySettingsStore(), badges: delivery,
            phase: phase
        )
        let window = try host(view)
        defer { window.isHidden = true }
        try await wait { await delivery.badges == [3] }
        await delivery.allowBadge()
        phase.value = .active
        try await wait { await delivery.badges.count == 2 }
        let again = await delivery.badges
        #expect(again == [3, 3])
        // Shown now: going away and back again leaves the icon alone, so a newer count a background check set stays (GAP-192).
        phase.value = .background
        try await Task.sleep(for: .milliseconds(100))
        phase.value = .active
        try await Task.sleep(for: .milliseconds(300))
        let after = await delivery.badges
        #expect(after == [3, 3])
    }
}
