import Foundation
import HFRModels
import HFRNetwork
import HFRStorage
import Observation
@testable import SwiftHFR
import SwiftUI
import Testing
import UIKit

/// #1404: on the iPhone Duo, each trip to the background flipped `usesSidebarRoot` twice (iOS lays the app out in the other size
/// class for its app-switcher snapshots), the swap rebuilt Favoris, whose appearance sent `GET /forum1f.php` in the background;
/// locked, that request froze and ended `timedOut` 25–56 s later, the error left on the list (device pass of #1388). The real
/// roots over fakes, with the scene phase the test sets, count what the lists ask for.
/// The scene phase the hosted views read, so a test can send the window away and back.
@MainActor
@Observable
private final class Phase {
    var value: ScenePhase = .active
    /// The hosted content is shown; false shows an empty window, so a test can show it later (or build it again).
    var showsContent = true
    /// What `SceneAwayTracking` is told of the app's state (the test host's own is always active).
    var appIsInBackground = false
}

private struct PhaseHost<Content: View>: View {
    let phase: Phase
    let content: Content

    var body: some View {
        Group {
            if phase.showsContent { content } else { Color.clear }
        }
        // As `RootNavigationView` does above the root.
        .tracksSceneAway { phase.appIsInBackground }
        .environment(\.scenePhase, phase.value)
    }
}

/// A request that hangs, as one iOS froze, until released, then fails `timedOut`; only the first call to `pass()` does.
private final class FrozenOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var released = false
    private var calls = 0

    func release() { lock.withLock { released = true } }

    func pass() async throws(ListLoadError) {
        let call = lock.withLock { calls += 1; return calls }
        guard call == 1 else { return }
        // Not cancellable on purpose: a request frozen with the app does not notice a cancellation either.
        while !lock.withLock({ released }) { try? await Task.sleep(for: .milliseconds(10)) }
        throw .timedOut
    }
}

@MainActor
@Suite(.serialized)
struct BackgroundListLoadHostedTests {
    private struct HostedRoot {
        let window: UIWindow
        let host: UIViewController
        let data: FakeDataSource
        let messages: FakePrivateMessages
    }

    // MARK: The root swap

    /// Favoris on the cover screen, the window away, then the snapshots' size classes: no swap, no request, before or after
    /// the return; and the same size change while active still swaps (a real unfold, LOT-147).
    @Test(.timeLimit(.minutes(2)))
    func theSnapshotsSizeClassesDoNotSwapTheRootNorReloadTheLists() async throws {
        let phase = Phase()
        let hosted = try hostRoot(phase: phase)
        defer { hosted.window.isHidden = true }
        let window = hosted.window
        #expect(await settle(window) { favoritesRequests(hosted.data) >= 1 && hasTabBar(window) })
        try await pause(window)
        let before = favoritesRequests(hosted.data)
        let messagesBefore = hosted.messages.requests.count

        phase.value = .inactive
        phase.value = .background
        try await pause(window)
        unfold(window, host: hosted.host)
        try await pause(window)
        #expect(hasTabBar(window), "a background snapshot swapped the root")
        fold(window, host: hosted.host)
        try await pause(window)
        #expect(favoritesRequests(hosted.data) == before, "requests in the background: \(hosted.data.requests)")
        #expect(hosted.messages.requests.count == messagesBefore)

        phase.value = .inactive
        phase.value = .active
        try await pause(window)
        #expect(hasTabBar(window))
        #expect(favoritesRequests(hosted.data) == before, "requests on return: \(hosted.data.requests)")

        // Control: an unfold while active is a real one and swaps.
        unfold(window, host: hosted.host)
        #expect(await settle(window) { !hasTabBar(window) }, "an unfold while active no longer swaps")
    }

    /// The phone unfolded while the app was away: the split comes on return, as the size classes say then.
    @Test(.timeLimit(.minutes(2)))
    func aFoldChangeMadeWhileAwaySwapsOnReturn() async throws {
        let phase = Phase()
        let hosted = try hostRoot(phase: phase)
        defer { hosted.window.isHidden = true }
        let window = hosted.window
        #expect(await settle(window) { hasTabBar(window) })
        phase.value = .background
        try await pause(window)
        unfold(window, host: hosted.host)
        try await pause(window)
        #expect(hasTabBar(window))
        phase.value = .active
        #expect(await settle(window) { !hasTabBar(window) }, "the unfold made while away was not applied on return")
    }

    // MARK: A list's own load

    /// A list that appears while the window is in the background loads once it is active, not before.
    @Test(.timeLimit(.minutes(2)))
    func aListAppearingInTheBackgroundLoadsOnReturn() async throws {
        let data = FakeDataSource()
        data.favoritesHandler = { _ in FavoritesPage(sections: [favoriteSection(13, [favoriteTopic(1)])]) }
        let model = TopicListModel(source: .favorites, dataSource: data, isLoggedIn: { true })
        let phase = Phase()
        phase.showsContent = false
        let window = try host(phase: phase, NavigationStack { TopicListView(model: model, selection: .constant(nil)) })
        defer { window.isHidden = true }
        phase.value = .inactive
        phase.value = .background
        try await pause(window)
        phase.showsContent = true
        try await pause(window)
        #expect(data.requests.isEmpty, "the list loaded in the background: \(data.requests)")

        phase.value = .active
        #expect(await settle(window) { model.loader.value != nil }, "the list did not load on return")
        #expect(data.requests.count == 1, "\(data.requests)")
    }

    /// A load in flight when the scene goes to the background is stopped, so the timeout iOS causes never reaches the list, and
    /// asked again on return.
    @Test(.timeLimit(.minutes(2)))
    func aLoadInFlightWhenTheSceneLeavesIsAskedAgainOnReturn() async throws {
        let data = FakeDataSource()
        let frozen = FrozenOnce()
        data.favoritesHandler = { _ async throws(ListLoadError) -> FavoritesPage in
            try await frozen.pass()
            return FavoritesPage(sections: [favoriteSection(13, [favoriteTopic(1)])])
        }
        let model = TopicListModel(source: .favorites, dataSource: data, isLoggedIn: { true })
        let phase = Phase()
        let window = try host(phase: phase, NavigationStack { TopicListView(model: model, selection: .constant(nil)) })
        defer { window.isHidden = true }
        #expect(await settle(window) { data.requests.count == 1 && model.loader.isLoading })

        phase.value = .inactive
        phase.value = .background
        #expect(await settle(window) { !model.loader.isLoading }, "the load kept running in the background")
        frozen.release()
        try await pause(window)
        #expect(model.loader.error == nil, "the frozen request's timeout reached the list")

        phase.value = .inactive
        phase.value = .active
        #expect(await settle(window) { model.loader.value != nil }, "the stopped load was not asked again")
        #expect(model.loader.error == nil)
        #expect(data.requests.count == 2)
    }
}

// MARK: Hosting

extension BackgroundListLoadHostedTests {
    func favoritesRequests(_ data: FakeDataSource) -> Int {
        data.requests.filter { $0.hasPrefix("favorites:") }.count
    }

    private func host(phase: Phase, _ content: some View) throws -> UIWindow {
        let view = PhaseHost(phase: phase, content: content).environment(makeModel(store: InMemoryCredentialStore()))
        let scene = try #require(UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = UIHostingController(rootView: view)
        window.isHidden = false
        window.layoutIfNeeded()
        return window
    }

    /// The real roots on the iPhone Duo's cover screen, Favoris shown, logged in.
    private func hostRoot(phase: Phase) throws -> HostedRoot {
        let data = FakeDataSource()
        data.favoritesHandler = { _ in FavoritesPage(sections: [favoriteSection(13, (1...3).map { favoriteTopic($0) })]) }
        let pages = FakeTopicPages { target in readerPage(page: target.page) }
        let forums = ForumListModel(dataSource: data)
        let messages = FakePrivateMessages()
        let root = RootModel(
            forums: forums,
            categories: NavigationModel(dataSource: data, forums: forums, topicPages: pages),
            favorites: NavigationModel(
                dataSource: data, forums: forums, sessionIsLoggedIn: { true }, topicPages: pages,
                startupSource: TopicSource(mode: .flagsAndFavorites)
            ),
            messages: MessageListModel(source: messages, isLoggedIn: { true }, topicPages: pages),
            store: InMemorySettingsStore(), initial: .tab(.favorites)
        )
        let view = RootLayout(model: root, environment: environment(data: data, pages: pages))
            .environment(\.rootLayoutIdiom, .phone)
            .environment(\.tabSplitIdiom, .phone)
            .environment(makeModel(store: InMemoryCredentialStore()))
        let scene = try #require(UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: PhaseHost(phase: phase, content: view))
        window.rootViewController = host
        fold(window, host: host)
        window.isHidden = false
        window.layoutIfNeeded()
        return HostedRoot(window: window, host: host, data: data, messages: messages)
    }

    private func environment(data: FakeDataSource, pages: FakeTopicPages) -> AppEnvironment {
        AppEnvironment(
            session: HFRSession(), dataSource: data, visibility: ForumVisibility(), currentAccountName: nil, topicPages: pages,
            reader: ReaderServices(
                imageFetcher: ReaderImageFetcher(transport: MockTransport(replies: [])),
                settings: ReaderSettings(
                    autoLoadsThirdPartyImages: { false }, renderOptions: { ReaderRenderOptions() }, swipesPages: { false }
                ),
                profiles: FakeUserProfiles([])
            ),
            privateMessages: FakePrivateMessages(), composer: nil, filteredPosts: .unavailable,
            favoriteStores: FavoritesStores(
                layout: FavoritesLayoutStore(persistence: InMemorySmallStorePersistence()),
                superFavorites: SuperFavoritesStore(persistence: InMemorySmallStorePersistence()), account: nil
            ),
            flagActions: nil, memberAvatars: nil,
            pseudoListsSnapshot: PseudoListsSnapshot(store: PseudoListStore(persistence: InMemoryPseudoListPersistence()), account: nil),
            blocklistChanges: nil, privateMessageCount: nil
        )
    }

    /// The inner screen: a portrait window regular in both dimensions (the snapshots' size classes on the Duo, #1388).
    private func unfold(_ window: UIWindow, host: UIViewController) {
        window.frame = CGRect(x: 0, y: 0, width: 1004, height: 1427)
        host.traitOverrides.horizontalSizeClass = .regular
        host.traitOverrides.verticalSizeClass = .regular
    }

    /// The cover screen: compact width, 466 × 678 pt.
    private func fold(_ window: UIWindow, host: UIViewController) {
        window.frame = CGRect(x: 0, y: 0, width: 466, height: 678)
        host.traitOverrides.horizontalSizeClass = .compact
        host.traitOverrides.verticalSizeClass = .regular
    }

    private func hasTabBar(_ window: UIWindow) -> Bool {
        var queue: [UIViewController] = window.rootViewController.map { [$0] } ?? []
        while !queue.isEmpty {
            let controller = queue.removeFirst()
            if controller is UITabBarController, controller.viewIfLoaded?.window != nil { return true }
            queue.append(contentsOf: controller.children)
        }
        return false
    }

    /// Lays out until `condition` holds, 30 s at most.
    private func settle(_ window: UIWindow, until condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(30)
        while ContinuousClock.now < deadline {
            window.layoutIfNeeded()
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return false
    }

    /// A few frames, for what a change would start.
    private func pause(_ window: UIWindow) async throws {
        for _ in 0..<10 {
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
        }
    }
}

// MARK: Round 1 of the review of #1414

/// A page of private messages `page` of `last`.
private func messagesPage(_ threads: [PrivateMessageThread], page: Int, last: Int) -> PrivateMessageListPage {
    PrivateMessageListPage(
        threads: threads,
        navigation: PageNavigation(
            current: page, last: last, nextPath: page < last ? "/next" : nil, previousPath: page > 1 ? "/prev" : nil
        )
    )
}

extension BackgroundListLoadHostedTests {
    /// Finding 1: « MP multiples » searching later pages when the window goes away. Stopping only the load let the search's
    /// loop ask for the same page again, in the background (`[1, 2, 2]`); it stops, and `retry()` resumes it on return.
    @Test(.timeLimit(.minutes(2)))
    func aSegmentSearchStoppedByTheLockSendsNothingMoreAndResumesOnReturn() async {
        let source = FakePrivateMessages()
        let gate = CheckGate()
        source.handler = { page in
            if page == 2 { await gate.wait() }
            let group = page == 3 ? [messageThread(99, group: true)] : []
            return messagesPage([messageThread(page)] + group, page: page, last: 4)
        }
        let store = InMemorySettingsStore()
        MPListSegmentStore(settings: store).set(.oneToOne, for: "Alice")
        let model = MessageListModel(source: source, isLoggedIn: { true }, settings: store, account: "Alice")
        await model.onAppear()
        let search = gate.run { await model.select(.group) }
        guard await gate.entered() else { Issue.record("The search never asked for page 2"); return }

        #expect(model.suspendLoad())
        await gate.open()
        await search.value
        try? await Task.sleep(for: .milliseconds(300))
        #expect(source.requests == [1, 2], "the search went on in the background")
        #expect(!model.loader.isLoading)
        #expect(model.loader.wasSuspended)

        await model.retry()
        #expect(source.requests == [1, 2, 2, 3])
        #expect(model.visibleThreads.map(\.id) == [messageThread(99, group: true).id])
        #expect(!model.loader.wasSuspended)
    }

    /// Finding 2: a window first built while the app is in the background (no move seen yet) is away from its first body, so
    /// its list's first `task` sends nothing.
    @Test(.timeLimit(.minutes(2)))
    func aListFirstBuiltInTheBackgroundLoadsOnlyOnReturn() async throws {
        let data = FakeDataSource()
        data.favoritesHandler = { _ in FavoritesPage(sections: [favoriteSection(13, [favoriteTopic(1)])]) }
        let model = TopicListModel(source: .favorites, dataSource: data, isLoggedIn: { true })
        let phase = Phase()
        phase.value = .background
        phase.appIsInBackground = true
        let window = try host(phase: phase, NavigationStack { TopicListView(model: model, selection: .constant(nil)) })
        defer { window.isHidden = true }
        try await pause(window)
        #expect(data.requests.isEmpty, "the list loaded in the background: \(data.requests)")

        phase.value = .active
        phase.appIsInBackground = false
        #expect(await settle(window) { model.loader.value != nil }, "the list did not load on return")
        #expect(data.requests.count == 1, "\(data.requests)")
    }

    /// Finding 3: a pager tap stopped by the lock is asked again on return even when the list was built again meanwhile (a fold
    /// made while away swaps the root on return): the model remembers it, not the view.
    @Test(.timeLimit(.minutes(2)))
    func aStoppedPageIsAskedAgainByAListBuiltAgainWhileAway() async throws {
        let data = FakeDataSource()
        let frozen = FrozenOnce()
        data.topicHandler = { _, page async throws(ListLoadError) -> TopicListPage in
            if page == 2 { try await frozen.pass() }
            return topicPage(page: page)
        }
        let model = TopicListModel(source: .forum(.forum(13), title: "Catégorie 13"), dataSource: data)
        let phase = Phase()
        let window = try host(phase: phase, NavigationStack { TopicListView(model: model, selection: .constant(nil)) })
        defer { window.isHidden = true }
        #expect(await settle(window) { model.loader.value != nil && !model.loader.isLoading })
        let next = Task { await model.goToNextPage() }
        #expect(await settle(window) { data.requests.contains("topics:13:2") && model.loader.isLoading })

        phase.value = .background
        #expect(await settle(window) { !model.loader.isLoading }, "the page load kept running in the background")
        phase.showsContent = false
        try await pause(window)
        phase.showsContent = true
        try await pause(window)
        frozen.release()
        await next.value

        phase.value = .active
        #expect(await settle(window) { model.currentPage == 2 }, "the stopped page was not asked again: \(data.requests)")
        #expect(data.requests.filter { $0 == "topics:13:2" }.count == 2, "\(data.requests)")
        #expect(model.loader.error == nil)
    }
}
