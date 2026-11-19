import HFRModels
import HFRNetwork
import HFRStorage
@testable import SwiftHFR
import SwiftUI
import Testing
import UIKit

/// LOT-147 (GAP-713): the real roots (`RootLayout`) in a cover-screen window (466 × 678 pt, compact width, the system chrome as
/// a side safe-area inset, the model not taken for a foldable so the inset alone is the signal) and, off a foldable, in a regular
/// iPhone window. On the cover screen « Actualiser » of Catégories and Messages is a bottom-bar item (the topic lists have none,
/// a pull refreshes them, #1206), a pushed topic list and a topic get « Retour » there; on a regular iPhone nothing is added. Read
/// from the items SwiftUI hands UIKit (`toolbarItems`, the navigation item's groups): its Liquid Glass bars hold no `UIControl`.
@MainActor
@Suite(.serialized)
struct CoverScreenThumbActionsTests: ReaderWebTesting {
    /// The screens of GAP-713: the four lists and the pushed topic.
    enum Screen: CaseIterable {
        case categories, topicList, favorites, messages, reader
    }

    private struct Hosted {
        let window: UIWindow
        let root: RootModel
    }

    /// The titles of the bar items on screen (spacers left out): the bottom bar's (`toolbarItems`) and the top bar's trailing ones.
    private struct Items: CustomStringConvertible {
        var bottom: [String] = []
        var topTrailing: [String] = []
        var description: String { "bottom \(bottom), top trailing \(topTrailing)" }
    }

    /// The Duo simulator's own screen has the side strip: every portrait window there is a cover screen, so a regular-iPhone
    /// control is meaningful only where the device is not a foldable (CI's iPhone simulator).
    nonisolated private static var isNotAFoldable: Bool { !PhoneDisplayPolicy.isFoldableModel(PhoneDisplayPolicy.currentModelIdentifier) }

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
            .environment(\.rootLayoutModelIdentifier, "iPhone18,1")
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
        return Hosted(window: window, root: root)
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

    /// A bar item's title; nil for a spacer, which the lists put before their items.
    private static func views(in view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap { views(in: $0) }
    }

    private static func title(of item: UIBarButtonItem) -> String? { item.title ?? item.accessibilityLabel }

    /// The bar items of the screens on view: SwiftUI hands its `.bottomBar` items to `toolbarItems` and its trailing ones to the
    /// navigation item's trailing groups (or `rightBarButtonItems`), with their titles.
    private static func read(_ window: UIWindow, controllers: [UIViewController]) -> Items {
        var items = Items()
        for controller in controllers {
            items.bottom += (controller.toolbarItems ?? []).compactMap(title(of:))
            let navigationItem = controller.navigationItem
            items.topTrailing += (navigationItem.rightBarButtonItems ?? []).compactMap(title(of:))
            items.topTrailing += navigationItem.trailingItemGroups.flatMap(\.barButtonItems).compactMap(title(of:))
        }
        return items
    }

    private func ready(_ screen: Screen, in window: UIWindow) -> Bool {
        switch screen {
        case .categories: shows("Catégories", in: window)
        case .topicList: shows("Catégorie 13", in: window)
        case .favorites: shows("Favoris", in: window)
        case .messages: shows("Messages", in: window)
        case .reader: shows("Sujet 1 p1", in: window)
        }
    }

    /// The screen's items once it is on view and `condition` holds (or the wait ends), with a layout pass each time.
    private func settle(_ screen: Screen, in window: UIWindow, until condition: (Items) -> Bool = { _ in true }) async -> Items {
        var items = Items()
        _ = await until({
            window.layoutIfNeeded()
            guard ready(screen, in: window) else { return false }
            items = Self.read(window, controllers: controllers(in: window))
            return condition(items)
        }, timeout: .seconds(30))
        return items
    }

    /// On the cover screen « Actualiser » of Catégories and Messages is a bottom-bar item, a pushed topic list and a topic get
    /// « Retour » there, first (above the page controls on a topic, legacy Mac check 2c); the Favoris root, neither pushed nor
    /// refreshed by a button (#1206), gets nothing; the topic keeps its top « Actualiser ».
    @Test(arguments: Screen.allCases)
    func theCoverScreenPutsTheThumbActionsInTheBottomBar(screen: Screen) async throws {
        let hosted = try host(screen, cover: true)
        defer { hosted.window.isHidden = true }
        let wanted: [String] = switch screen {
        case .topicList, .reader: ["Retour"]
        case .favorites: []
        case .categories, .messages: ["Actualiser"]
        }
        var items = await settle(screen, in: hosted.window) { Array($0.bottom.prefix(wanted.count)) == wanted }
        if screen == .favorites {
            // Nothing to wait for: a later layout pass is given its chance to add an item it should not.
            try await Task.sleep(for: .milliseconds(500))
            items = await settle(screen, in: hosted.window)
        }
        print("CoverScreenThumbActionsTests cover \(screen): \(items)")
        #expect(Array(items.bottom.prefix(wanted.count)) == wanted, "\(screen): \(items)")
        #expect(items.topTrailing.contains("Actualiser") == (screen == .reader), "\(screen): \(items)")
        if screen != .topicList, screen != .reader { #expect(!items.bottom.contains("Retour"), "\(screen): \(items)") }
        if screen != .categories, screen != .messages { #expect(!items.bottom.contains("Actualiser"), "\(screen): \(items)") }
    }

    /// Off the cover screen nothing is added: the lists have no bottom-bar item (the pager is an inset there, #565) and no
    /// « Actualiser » button (a pull refreshes them, #1206), the topic's bottom bar is its page controls with no « Retour ».
    @Test(.enabled(if: Self.isNotAFoldable), arguments: Screen.allCases)
    func aRegularIPhoneKeepsItsBars(screen: Screen) async throws {
        let hosted = try host(screen, cover: false)
        defer { hosted.window.isHidden = true }
        let hasTopRefresh = screen == .reader
        let items = await settle(screen, in: hosted.window) { !hasTopRefresh || $0.topTrailing.contains("Actualiser") }
        print("CoverScreenThumbActionsTests regular \(screen): \(items)")
        #expect(!items.bottom.contains("Retour"), "\(screen): \(items)")
        #expect(!items.bottom.contains("Actualiser"), "\(screen): \(items)")
        #expect(items.topTrailing.contains("Actualiser") == hasTopRefresh, "\(screen): \(items)")
    }

    /// On a foldable (the Duo simulator's own cover screen, 466 × 678 pt), the lists' bottom-bar items are drawn in the lower
    /// half of the column, right above the tab bar, not under the top items: iOS 27.2 lays them in an empty trailing slot and
    /// honours their flexible spacer only once that slot holds an item (`AccountMenuButton.placement(on:)`). Measured before the
    /// fix at y 239 (Catégories, Messages) and 299 (« Retour » of a pushed list); after it at 387, the tab bar at 442. A regular
    /// iPhone has no column: the bar is the system bottom bar, left to `aRegularIPhoneKeepsItsBars`.
    @Test(.enabled(if: !Self.isNotAFoldable), arguments: [Screen.categories, .topicList, .messages])
    func onTheDuoTheListsActionsSitAboveTheTabBar(screen: Screen) async throws {
        let hosted = try host(screen, cover: true)
        defer { hosted.window.isHidden = true }
        let count = 1
        _ = await settle(screen, in: hosted.window) { $0.bottom.count >= count }
        try await Task.sleep(for: .milliseconds(500))
        hosted.window.layoutIfNeeded()
        let window = hosted.window
        // The strip's bar buttons: the buttons drawn in the right-edge column (the tab buttons carry no button trait).
        let tops = Self.views(in: window).compactMap { $0 as? UIControl }
            .filter { $0.window != nil && !$0.isHidden && $0.alpha > 0.01 && $0.accessibilityTraits.contains(.button) }
            .map { window.convert($0.bounds, from: $0) }
            .filter { $0.minX > window.bounds.width - 70 }
            .map(\.minY).sorted()
        let lowest = tops.suffix(count)
        print("CoverScreenThumbActionsTests strip \(screen): \(tops)")
        #expect(lowest.count == count && lowest.allSatisfy { $0 > window.bounds.midY }, "\(screen): strip buttons at \(tops)")
    }

    /// « Retour » goes back: on the pushed topic list it pops to Catégories (the collapsed split clears the forum), on the topic
    /// it closes it (the selection cleared, so an unfold does not bring it back, as the system back button does).
    @Test(arguments: [Screen.topicList, .reader])
    func retourGoesBack(screen: Screen) async throws {
        let hosted = try host(screen, cover: true)
        defer { hosted.window.isHidden = true }
        let (window, root) = (hosted.window, hosted.root)
        let items = await settle(screen, in: window) { $0.bottom.contains("Retour") }
        let retour = try #require(
            controllers(in: window).flatMap { $0.toolbarItems ?? [] }.first { Self.title(of: $0) == "Retour" }, "\(screen): \(items)"
        )
        // SwiftUI's bar items carry a `UIAction`; a control given that action runs it, as a tap on the button does.
        if let target = retour.target, let action = retour.action {
            _ = UIApplication.shared.sendAction(action, to: target, from: retour, for: nil)
        } else if let primary = retour.primaryAction as UIAction? {
            UIButton(primaryAction: primary).sendActions(for: .primaryActionTriggered)
        } else {
            Issue.record("\(screen): « Retour » has no action")
        }
        let back = await until({
            window.layoutIfNeeded()
            return screen == .topicList ? root.categories.selectedSource == nil : root.favorites.selectedTopic == nil
        }, timeout: .seconds(10))
        let left = "forum \(String(describing: root.categories.selectedSource)), topic \(String(describing: root.favorites.selectedTopic))"
        #expect(back, "\(screen): « Retour » did not go back; \(left)")
    }
}
