import HFRModels
import HFRNetwork
import HFRStorage
@testable import SwiftHFR
import SwiftUI
import Testing
import UIKit

/// LOT-147 (GAP-713): the real roots (`RootLayout`) in a cover-screen window (466 × 678 pt, compact width, the system chrome as
/// a side safe-area inset, the model not taken for a foldable so the inset alone is the signal) and in a regular iPhone window.
/// On the cover screen « Actualiser » of the four lists is a bottom-bar item, a pushed topic list and a topic get « Retour »
/// there; on a regular iPhone nothing is added and the forum list's « Actualiser » stays in the top bar.
@MainActor
@Suite(.serialized)
struct CoverScreenThumbActionsTests: ReaderWebTesting {
    /// The screens of GAP-713: the four lists and the pushed topic.
    enum Screen: CaseIterable {
        case categories, topicList, favorites, messages, reader
    }

    private struct Hosted {
        let window: UIWindow
        let host: UIViewController
        let root: RootModel
    }

    /// The shown controls of the bars, bottom and top-right, with what was seen for a failure message.
    private struct Bars {
        var bottom: [UIControl] = []
        var topRight = 0
        var diagnostics = ""
    }

    nonisolated private static func page(for target: ReaderTarget) -> ReaderPage {
        guard case .topic(let topic) = target.source else { return readerPage(page: target.page) }
        var page = readerPage(page: target.page, title: "Sujet \(topic.topic) p\(target.page)")
        page.topicID = topic
        return page
    }

    private func host(_ screen: Screen, cover: Bool) throws -> Hosted {
        let data = FakeDataSource()
        data.favoritesHandler = { _ in FavoritesPage(sections: [favoriteSection(13, (1...3).map { favoriteTopic($0) })]) }
        let pages = FakeTopicPages { target in Self.page(for: target) }
        let forums = ForumListModel(dataSource: data)
        let messages = FakePrivateMessages()
        let initial: SidebarDestination = switch screen {
        case .categories, .topicList: .tab(.categories)
        case .favorites, .reader: .tab(.favorites)
        case .messages: .tab(.messages)
        }
        let root = RootModel(
            forums: forums,
            categories: NavigationModel(dataSource: data, forums: forums, topicPages: pages),
            favorites: NavigationModel(dataSource: data, forums: forums, sessionIsLoggedIn: { true }, topicPages: pages,
                                       startupSource: RootModel.favoritesStartupSource),
            messages: MessageListModel(source: messages, isLoggedIn: { true }, topicPages: pages),
            store: InMemorySettingsStore(), initial: initial
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
            // Not a foldable by its model: on the cover window the side inset is the only signal, on the regular window none is.
            .environment(\.rootLayoutFoldableModel, false)
            .environment(makeModel(store: InMemoryCredentialStore()))
        let scene = try #require(UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: view)
        window.rootViewController = host
        if cover {
            // The cover screen (#1083): compact width, and the system strip on the right edge (Mac check of `87fe0d1c` on #372, 2a).
            window.frame = CGRect(x: 0, y: 0, width: 466, height: 678)
            host.additionalSafeAreaInsets = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 44)
        } else {
            window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        }
        host.traitOverrides.horizontalSizeClass = .compact
        host.traitOverrides.verticalSizeClass = .regular
        window.isHidden = false
        window.layoutIfNeeded()
        switch screen {
        case .topicList: root.categories.selectedSource = .forum(.forum(13), title: "Catégorie 13")
        case .reader: root.favorites.selectedTopic = favoriteTopic(1)
        default: break
        }
        return Hosted(window: window, host: host, root: root)
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

    private func shows(_ title: String, in window: UIWindow) -> Bool {
        controllers(in: window).compactMap { $0 as? UINavigationController }
            .contains { $0.viewControllers.last?.navigationItem.title == title }
    }

    private static func views(in view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap { views(in: $0) }
    }

    /// In the window, with no hidden or transparent view between it and `bar` (UIKit keeps transition copies at alpha 0).
    private static func isShown(_ view: UIView, below bar: UIView) -> Bool {
        guard view.window != nil else { return false }
        var current: UIView? = view
        while let node = current, node !== bar {
            if node.isHidden || node.alpha <= 0.01 { return false }
            current = node.superview
        }
        return current === bar
    }

    /// The accessibility label of a control or of one of its views (SwiftUI's bar buttons carry it on a subview).
    private static func label(of control: UIView) -> String? {
        views(in: control).lazy.compactMap(\.accessibilityLabel).first
    }

    /// The shown controls of the window's bars: a `UIToolbar`'s are the bottom bar's (where `.bottomBar` items go), the controls
    /// drawn in the right half of a `UINavigationBar` are its trailing items. The tab bar and the pull-to-refresh control are no bars.
    private static func read(_ window: UIWindow) -> Bars {
        var bars = Bars()
        let all = views(in: window).filter { $0 is UINavigationBar || $0 is UIToolbar }.filter { !$0.isHidden && $0.alpha > 0 }
        bars.diagnostics = "\(all.count) bar(s)"
        for bar in all {
            let controls = views(in: bar).compactMap { $0 as? UIControl }
                .filter { isShown($0, below: bar) && !$0.bounds.isEmpty && !($0 is UIRefreshControl) }
            let named = controls.map { "\(type(of: $0))(\(label(of: $0) ?? "-"))@\(Int(bar.convert($0.bounds, from: $0).midX))" }
            bars.diagnostics += "; \(type(of: bar)) \(bar.bounds.size): " + named.joined(separator: ",")
            if bar is UIToolbar {
                bars.bottom += controls
            } else {
                bars.topRight += controls.filter { bar.convert($0.bounds, from: $0).midX > bar.bounds.midX }.count
            }
        }
        return bars
    }

    private func settle(_ window: UIWindow, until condition: (Bars) -> Bool) async -> Bars {
        var bars = Bars()
        _ = await until({
            window.layoutIfNeeded()
            bars = Self.read(window)
            return condition(bars)
        }, timeout: .seconds(30))
        return bars
    }

    private func ready(_ screen: Screen, in window: UIWindow) -> Bool {
        switch screen {
        case .topicList: shows("Catégorie 13", in: window)
        case .reader: shows("Sujet 1 p1", in: window)
        default: true
        }
    }

    /// How many bottom-bar controls the screen has on a regular iPhone: none on a list (the pager is an inset there, #565), the
    /// page controls on a topic (`ReaderBottomBar.placement`: the tab bar is hidden, so `.bottomBar`).
    private func baseline(_ screen: Screen) async throws -> Int {
        let hosted = try host(screen, cover: false)
        defer { hosted.window.isHidden = true }
        let bars = await settle(hosted.window) { _ in ready(screen, in: hosted.window) }
        try await Task.sleep(for: .milliseconds(300))
        let settled = Self.read(hosted.window)
        print("CoverScreenThumbActionsTests regular \(screen): \(settled.diagnostics)")
        #expect(ready(screen, in: hosted.window), "\(screen) not shown: \(bars.diagnostics)")
        return settled.bottom.count
    }

    /// On the cover screen each list gains one bottom-bar control, « Actualiser » (two with « Retour » on a pushed list), and the
    /// topic gains « Retour » over its page controls; on a regular iPhone the bottom bar has what it had.
    @Test(arguments: Screen.allCases)
    func theCoverScreenPutsTheThumbActionsInTheBottomBar(screen: Screen) async throws {
        let regular = try await baseline(screen)
        let hosted = try host(screen, cover: true)
        defer { hosted.window.isHidden = true }
        let added = screen == .topicList ? 2 : 1
        let bars = await settle(hosted.window) { ready(screen, in: hosted.window) && $0.bottom.count >= regular + added }
        print("CoverScreenThumbActionsTests cover \(screen): \(bars.diagnostics)")
        #expect(bars.bottom.count == regular + added, "\(screen): \(regular) bottom control(s) on a regular iPhone; cover: \(bars.diagnostics)")
    }

    /// The forum list's « Actualiser » leaves the top bar on the cover screen: the only trailing item there (no composer, no
    /// favourites filter) is gone, where a regular iPhone keeps it.
    @Test(arguments: [true, false])
    func theTopicListsRefreshLeavesTheTopBarOnTheCoverScreen(cover: Bool) async throws {
        let hosted = try host(.topicList, cover: cover)
        defer { hosted.window.isHidden = true }
        let bars = await settle(hosted.window) { ready(.topicList, in: hosted.window) && ($0.topRight > 0) != cover }
        print("CoverScreenThumbActionsTests top bar cover=\(cover): \(bars.diagnostics)")
        #expect((bars.topRight > 0) != cover, "cover \(cover): \(bars.diagnostics)")
    }

    /// « Retour » goes back: on the pushed topic list it pops to Catégories (the collapsed split clears the forum), on the topic
    /// it closes it (the selection cleared, so an unfold does not bring it back, as the system back button).
    @Test(arguments: [Screen.topicList, .reader])
    func retourGoesBack(screen: Screen) async throws {
        let hosted = try host(screen, cover: true)
        defer { hosted.window.isHidden = true }
        let (window, root) = (hosted.window, hosted.root)
        let bars = await settle(window) { ready(screen, in: window) && $0.bottom.contains { Self.label(of: $0) == "Retour" } }
        let retour = try #require(bars.bottom.first { Self.label(of: $0) == "Retour" }, "no « Retour »: \(bars.diagnostics)")
        retour.sendActions(for: .primaryActionTriggered)
        let back = await until({
            window.layoutIfNeeded()
            return screen == .topicList ? root.categories.selectedSource == nil : root.favorites.selectedTopic == nil
        }, timeout: .seconds(10))
        #expect(back, "\(screen): « Retour » did not go back; forum \(String(describing: root.categories.selectedSource)), "
            + "topic \(String(describing: root.favorites.selectedTopic))")
    }
}
