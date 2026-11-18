import HFRModels
import HFRNetwork
import HFRStorage
@testable import SwiftHFR
import SwiftUI
import Testing
import UIKit

/// LOT-147 (GAP-210, GAP-213, GAP-215, GAP-217): the iPhone Duo as legacy has it at `87fe0d1c` (`2fe43da3` for the layout). The
/// inner screen, a `.phone` regular in both dimensions, gets the split root, its topic full width in portrait; the rotation
/// setting does not lock it; a fold or an unfold keeps the topic read and its page, not the readers its links pushed.
@MainActor
struct DuoLayoutTests {
    // MARK: Split root (`MainWindow.swift:1380-1388` @ 87fe0d1c)

    @Test func aPhoneRegularInBothDimensionsGetsTheSplitRoot() {
        #expect(RootNavigationView.usesSidebarRoot(idiom: .phone, horizontal: .regular, vertical: .regular))
        #expect(!RootNavigationView.rootHasTabBar(idiom: .phone, horizontal: .regular, vertical: .regular))
    }

    @Test func theCoverScreenAndALandscapeProMaxKeepTheTabBar() {
        // The Duo's cover screen (compact width) and a regular iPhone in portrait.
        #expect(!RootNavigationView.usesSidebarRoot(idiom: .phone, horizontal: .compact, vertical: .regular))
        // A Plus or Pro Max in landscape: regular width, compact height.
        #expect(!RootNavigationView.usesSidebarRoot(idiom: .phone, horizontal: .regular, vertical: .compact))
        #expect(!RootNavigationView.usesSidebarRoot(idiom: .phone, horizontal: .compact, vertical: .compact))
        #expect(!RootNavigationView.usesSidebarRoot(idiom: .phone, horizontal: nil, vertical: .regular))
    }

    @Test func anIPadKeepsItsRegularWidthRule() {
        #expect(RootNavigationView.usesSidebarRoot(idiom: .pad, horizontal: .regular, vertical: .regular))
        #expect(RootNavigationView.usesSidebarRoot(idiom: .pad, horizontal: .regular, vertical: .compact))
        #expect(!RootNavigationView.usesSidebarRoot(idiom: .pad, horizontal: .compact, vertical: .regular))
        #expect(!RootNavigationView.usesSidebarRoot(idiom: .pad, horizontal: nil, vertical: nil))
    }

    // MARK: Rotation (`Common.swift:187-200` @ 87fe0d1c, GAP-213)

    @Test func theUnfoldedDuoRotatesWhateverTheSetting() {
        #expect(OrientationPolicy.supported(idiom: .phone, rotationAllowed: false, expanded: true) == .allButUpsideDown)
        #expect(OrientationPolicy.supported(idiom: .phone, rotationAllowed: true, expanded: true) == .allButUpsideDown)
        // Folded, the lock applies again.
        #expect(OrientationPolicy.supported(idiom: .phone, rotationAllowed: false, expanded: false) == .portrait)
        #expect(OrientationPolicy.supported(idiom: .pad, rotationAllowed: false, expanded: true) == .all)
    }

    @Test func theStoredLockDoesNotApplyUnfolded() {
        let locked = InMemorySettingsStore(["landscape_mode": .string("none")])
        #expect(OrientationPolicy.supported(idiom: .phone, store: locked, expanded: true) == .allButUpsideDown)
        #expect(OrientationPolicy.supported(idiom: .phone, store: locked, expanded: false) == .portrait)
    }

    @Test func onlyRegularInBothDimensionsIsExpanded() {
        let both = UITraitCollection { $0.horizontalSizeClass = .regular; $0.verticalSizeClass = .regular }
        let cover = UITraitCollection { $0.horizontalSizeClass = .compact; $0.verticalSizeClass = .regular }
        let landscape = UITraitCollection { $0.horizontalSizeClass = .regular; $0.verticalSizeClass = .compact }
        #expect(OrientationPolicy.isExpanded(both))
        #expect(!OrientationPolicy.isExpanded(cover))
        #expect(!OrientationPolicy.isExpanded(landscape))
    }

    // MARK: Topic full width in portrait (`prefersDetailOnlyTopic`, `MainWindow.swift:1390-1396` @ 87fe0d1c)

    @Test func onlyAPhoneInPortraitPrefersTheTopicAlone() {
        #expect(DuoSplitColumns.prefersDetailOnlyTopic(idiom: .phone, isPortrait: true))
        #expect(!DuoSplitColumns.prefersDetailOnlyTopic(idiom: .phone, isPortrait: false))
        #expect(!DuoSplitColumns.prefersDetailOnlyTopic(idiom: .pad, isPortrait: true))
    }

    @Test func aTopicOpenedInPortraitTakesTheFullWidth() {
        for current in [NavigationSplitViewVisibility.all, .doubleColumn, .automatic] {
            let next = DuoSplitColumns.visibility(current, detailOnlyTopic: true, wasDetailOnlyTopic: true, hasTopic: true)
            #expect(next == .detailOnly, "from \(current)")
        }
    }

    @Test func landscapeOrNoTopicShowsTheListAgain() {
        // Rotated to landscape with a topic open: list and topic.
        #expect(DuoSplitColumns.visibility(.detailOnly, detailOnlyTopic: false, wasDetailOnlyTopic: true, hasTopic: true) == .doubleColumn)
        // The topic closed (a deleted MP or bookmark, another destination): never an empty detail with the list hidden.
        #expect(DuoSplitColumns.visibility(.detailOnly, detailOnlyTopic: true, wasDetailOnlyTopic: true, hasTopic: false) == .doubleColumn)
        let noTopic = DuoSplitColumns.visibility(.detailOnly, detailOnlyTopic: false, wasDetailOnlyTopic: false, hasTopic: false)
        #expect(noTopic == .doubleColumn)
    }

    @Test func otherChangesKeepTheUsersChoice() {
        // An iPad whose user hid the columns keeps them hidden while a topic is open.
        #expect(DuoSplitColumns.visibility(.detailOnly, detailOnlyTopic: false, wasDetailOnlyTopic: false, hasTopic: true) == .detailOnly)
        // No topic in portrait: the columns stay as they are (SwiftHFR starts with all of them, an intentional difference).
        #expect(DuoSplitColumns.visibility(.all, detailOnlyTopic: true, wasDetailOnlyTopic: false, hasTopic: false) == .all)
        let shown = DuoSplitColumns.visibility(.doubleColumn, detailOnlyTopic: false, wasDetailOnlyTopic: true, hasTopic: true)
        #expect(shown == .doubleColumn)
    }

    // MARK: Fold handoff (GAP-217)

    @Test func aTabSplitStartsOnTheReaderWhenItsTopicIsOpen() {
        #expect(NavigationSplitViewColumn.compactStart(showsTopic: true) == .detail)
        #expect(NavigationSplitViewColumn.compactStart(showsTopic: false) == .sidebar)
    }
}

/// The real roots (`RootLayout`) over fakes in a window whose size classes a fold or an unfold changes: the iPhone Duo's inner
/// screen (regular in both dimensions, 1004 × 1427 pt in portrait) and its cover screen (compact width, 466 × 678 pt).
@MainActor
@Suite(.serialized)
struct DuoLayoutHostedTests: ReaderWebTesting {
    private struct Hosted {
        let window: UIWindow
        let host: UIViewController
        let root: RootModel
    }

    nonisolated private static func page(for target: ReaderTarget) -> ReaderPage {
        guard case .topic(let topic) = target.source else { return readerPage(page: target.page) }
        var page = readerPage(page: target.page, title: "Sujet \(topic.topic) p\(target.page)")
        page.topicID = topic
        return page
    }

    private func host() throws -> Hosted {
        let data = FakeDataSource()
        data.favoritesHandler = { _ in FavoritesPage(sections: [favoriteSection(13, (1...3).map { favoriteTopic($0) })]) }
        let pages = FakeTopicPages { target in Self.page(for: target) }
        let forums = ForumListModel(dataSource: data)
        let root = RootModel(
            forums: forums,
            categories: NavigationModel(dataSource: data, forums: forums, topicPages: pages),
            favorites: NavigationModel(dataSource: data, forums: forums, sessionIsLoggedIn: { true }, topicPages: pages,
                                       startupSource: RootModel.favoritesStartupSource),
            messages: MessageListModel(source: FakePrivateMessages()),
            store: InMemorySettingsStore(), initial: .tab(.favorites)
        )
        let services = ReaderServices(
            imageFetcher: ReaderImageFetcher(transport: MockTransport(replies: [])),
            settings: ReaderSettings(
                autoLoadsThirdPartyImages: { false }, renderOptions: { ReaderRenderOptions() }, swipesPages: { false }
            ),
            profiles: FakeUserProfiles([])
        )
        let environment = AppEnvironment(
            session: HFRSession(), dataSource: data, visibility: ForumVisibility(), currentAccountName: nil, topicPages: pages,
            reader: services, privateMessages: FakePrivateMessages(), composer: nil, filteredPosts: .unavailable,
            favoriteStores: FavoritesStores(
                layout: FavoritesLayoutStore(persistence: InMemorySmallStorePersistence()),
                superFavorites: SuperFavoritesStore(persistence: InMemorySmallStorePersistence()), account: nil
            ),
            flagActions: nil, memberAvatars: nil,
            pseudoListsSnapshot: PseudoListsSnapshot(store: PseudoListStore(persistence: InMemoryPseudoListPersistence()), account: nil),
            blocklistChanges: nil, privateMessageCount: nil
        )
        let view = RootLayout(model: root, environment: environment)
            .environment(\.rootLayoutIdiom, .phone)
            .environment(\.tabSplitIdiom, .phone)
            .environment(makeModel(store: InMemoryCredentialStore()))
        let scene = try #require(UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: view)
        window.rootViewController = host
        unfold(window, host: host)
        window.isHidden = false
        window.layoutIfNeeded()
        return Hosted(window: window, host: host, root: root)
    }

    private func unfold(_ window: UIWindow, host: UIViewController) {
        window.frame = CGRect(x: 0, y: 0, width: 1004, height: 1427)
        host.traitOverrides.horizontalSizeClass = .regular
        host.traitOverrides.verticalSizeClass = .regular
    }

    private func fold(_ window: UIWindow, host: UIViewController) {
        window.frame = CGRect(x: 0, y: 0, width: 466, height: 678)
        host.traitOverrides.horizontalSizeClass = .compact
        host.traitOverrides.verticalSizeClass = .regular
    }

    private func controllers(in window: UIWindow) -> [UIViewController] {
        var result: [UIViewController] = []
        var queue: [UIViewController] = window.rootViewController.map { [$0] } ?? []
        while !queue.isEmpty {
            let controller = queue.removeFirst()
            if controller.viewIfLoaded?.window != nil { result.append(controller) }
            queue.append(contentsOf: controller.children)
            if let presented = controller.presentedViewController { queue.append(presented) }
        }
        return result
    }

    /// The title stacks of the navigation controllers on screen: a pushed reader is a second title.
    private func stacks(in window: UIWindow) -> [[String]] {
        controllers(in: window).compactMap { $0 as? UINavigationController }.map {
            $0.viewControllers.map { $0.navigationItem.title ?? "" }
        }
    }

    private func split(in window: UIWindow) -> UISplitViewController? {
        controllers(in: window).lazy.compactMap { $0 as? UISplitViewController }.first { !$0.isCollapsed && $0.style == .tripleColumn }
    }

    private func hasTabBar(_ window: UIWindow) -> Bool {
        controllers(in: window).contains { $0 is UITabBarController }
    }

    private func shows(_ title: String, in window: UIWindow) -> Bool {
        stacks(in: window).contains { $0.last == title }
    }

    private func settle(_ window: UIWindow, until condition: () -> Bool) async -> Bool {
        await until({
            window.layoutIfNeeded()
            return condition()
        }, timeout: .seconds(30))
    }

    /// Unfolded in portrait, the Favoris split shows its list until a topic opens, then the topic alone (legacy
    /// `prefersDetailOnlyTopic`); with the iPad's rule (`.pad`) the window would have stayed a tab bar before LOT-147.
    @Test func theUnfoldedDuoShowsTheSplitThenTheTopicAlone() async throws {
        let hosted = try host()
        defer { hosted.window.isHidden = true }
        let window = hosted.window
        #expect(await settle(window) { split(in: window) != nil }, "no split root: tab bar \(hasTabBar(window))")
        #expect(!hasTabBar(window))
        #expect(split(in: window)?.displayMode != .secondaryOnly)

        hosted.root.favorites.selectedTopic = favoriteTopic(1)
        let alone = await settle(window) { shows("Sujet 1 p1", in: window) && split(in: window)?.displayMode == .secondaryOnly }
        #expect(alone, "display mode \(String(describing: split(in: window)?.displayMode.rawValue)), \(stacks(in: window))")
    }

    /// A fold hands the topic, on its page, to the cover screen's tab root, without the reader a link had pushed over it; an
    /// unfold hands it back to the split (legacy `handleRootSwap`, `FoldHandoffStore`, `MainWindow.swift:2140-2183` @ 87fe0d1c).
    @Test func aFoldAndAnUnfoldKeepTheTopicAndItsPage() async throws {
        let hosted = try host()
        defer { hosted.window.isHidden = true }
        let (window, root) = (hosted.window, hosted.root)
        let topic = try #require(favoriteTopic(1).topicID)
        root.favorites.selectedTopic = favoriteTopic(1)
        let reader = try #require(root.favorites.reader(for: favoriteTopic(1)))
        #expect(await settle(window) { reader.page != nil && shows("Sujet 1 p1", in: window) }, "\(stacks(in: window))")
        reader.follow(ReaderTarget(source: .topic(topic), page: 4))
        let linked = try #require(reader.linkedReader)
        #expect(await settle(window) { linked.page != nil && shows("Sujet 1 p4", in: window) }, "\(stacks(in: window))")

        fold(window, host: hosted.host)
        let folded = await settle(window) { hasTabBar(window) && shows("Sujet 1 p1", in: window) }
        #expect(folded, "folded: tab bar \(hasTabBar(window)), \(stacks(in: window))")
        #expect(!shows("Sujet 1 p4", in: window), "the pushed reader was carried: \(stacks(in: window))")
        #expect(reader.linkedReader == nil)
        #expect(root.favorites.reader(for: favoriteTopic(1)) === reader, "the reader (and its page) was not kept")

        unfold(window, host: hosted.host)
        let unfolded = await settle(window) { !hasTabBar(window) && split(in: window) != nil && shows("Sujet 1 p1", in: window) }
        #expect(unfolded, "unfolded: tab bar \(hasTabBar(window)), \(stacks(in: window))")
        #expect(root.favorites.reader(for: favoriteTopic(1)) === reader)
    }

    /// Back on the cover screen closes the topic, so an unfold does not bring it back (legacy `handleRootSwap`: nothing read,
    /// no older split selection, `MainWindow.swift:2157-2160` @ 87fe0d1c).
    @Test func aTopicClosedOnTheCoverScreenDoesNotComeBackUnfolded() async throws {
        let hosted = try host()
        defer { hosted.window.isHidden = true }
        let (window, root) = (hosted.window, hosted.root)
        root.favorites.selectedTopic = favoriteTopic(1)
        #expect(await settle(window) { shows("Sujet 1 p1", in: window) }, "\(stacks(in: window))")
        fold(window, host: hosted.host)
        #expect(await settle(window) { hasTabBar(window) && shows("Sujet 1 p1", in: window) }, "\(stacks(in: window))")

        let stack = try #require(controllers(in: window).lazy.compactMap { $0 as? UINavigationController }.first {
            $0.viewControllers.last?.navigationItem.title == "Sujet 1 p1" && $0.viewControllers.count > 1
        })
        stack.popViewController(animated: false)
        #expect(await settle(window) { root.favorites.selectedTopic == nil }, "back kept the selection: \(stacks(in: window))")

        unfold(window, host: hosted.host)
        #expect(await settle(window) { !hasTabBar(window) && split(in: window) != nil })
        try await Task.sleep(for: .milliseconds(500))
        #expect(!shows("Sujet 1 p1", in: window), "the closed topic came back: \(stacks(in: window))")
        #expect(root.favorites.selectedTopic == nil)
    }
}
