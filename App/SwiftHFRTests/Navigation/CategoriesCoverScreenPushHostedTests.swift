import Foundation
import HFRModels
import HFRNetwork
import HFRStorage
@testable import SwiftHFR
import SwiftUI
import Testing
import UIKit

/// The hosted Catégories tab and the models a test checks.
private struct HostedCategoriesTab {
    let window: UIWindow
    let navigation: NavigationModel
    let data: FakeDataSource
}

/// #681: on the iPhone Duo's cover screen, opening a category once the Catégories list had been scrolled froze the legacy app (beta
/// 4.0.4, #372): a collapsed system large title, then a push, looped in `UINavigationController`'s layout on that screen's side
/// safe-area strip. The Catégories tab as `RootTabsView` builds it (tab view that minimizes on scroll, collapsed split view),
/// hosted in a window of the whole screen of the simulator the test runs on, so on the iPhone Duo simulator (which boots folded)
/// the cover screen's size, traits and safe area. The list is scrolled to its end, then the last category is selected as a tap
/// selects it: through the list's collection view delegate, on the row that shows it.
///
/// SwiftHFR has no system large title since #998 (the large title is a list row, the bar stays inline), so legacy's precondition is
/// gone; this guards the sequence, and a watchdog names the step a main-thread hang stops after. Measured on the iPhone Duo
/// simulator (iOS 27.2): 466 × 678 pt, safe area right 84 pt, compact width; the sequence passes, also with the system large title
/// put back on Catégories, so the legacy loop itself does not show in a hosted test there: the physical Duo stays the check.
@MainActor
@Suite(.serialized)
struct CategoriesCoverScreenPushHostedTests {
    /// The last category of the list: far enough down that the list must scroll to show it.
    private nonisolated static let lastCategory = 34

    private func readerServices() -> ReaderServices {
        ReaderServices(
            imageFetcher: ReaderImageFetcher(transport: MockTransport(replies: [])),
            settings: ReaderSettings(
                autoLoadsThirdPartyImages: { false }, renderOptions: { ReaderRenderOptions() }, swipesPages: { false }
            ),
            profiles: FakeUserProfiles([])
        )
    }

    /// 22 categories of 8 sub-forums each, signed in.
    private func dataSource() -> FakeDataSource {
        let data = FakeDataSource()
        data.forumHandler = {
            ForumListPage(forums: (13...Self.lastCategory).map { category in
                ForumCategory(
                    categoryID: .forum(category), title: "Catégorie \(category)", path: "/c\(category)",
                    subforums: (1...8).map { ForumLink(title: "Sous-forum \($0)", path: "/c\(category)/s\($0)") }
                )
            }, isLoggedIn: true)
        }
        return data
    }

    /// The Catégories tab, with Favoris beside it, hosted in a window of the whole screen.
    private func hostCategoriesTab(density: ListDensity) async throws -> HostedCategoriesTab {
        let data = dataSource()
        let store = InMemorySettingsStore()
        let filter = TopicFilterModel(settings: store)
        let forums = ForumListModel(dataSource: data)
        let navigation = NavigationModel(dataSource: data, forums: forums, sessionIsLoggedIn: { true }, topicFilter: filter)
        let favorites = NavigationModel(
            dataSource: data, forums: forums, sessionIsLoggedIn: { true }, startupSource: .favorites,
            favorites: favoritesOptions(settings: store), topicFilter: filter
        )
        await forums.loadIfNeeded()
        let root = TabView(selection: .constant(RootTab.categories)) {
            Tab(RootTab.categories.title, systemImage: RootTab.categories.symbol, value: RootTab.categories) {
                CategoriesTabView(navigation: navigation, reader: readerServices(), composer: nil)
            }
            Tab(RootTab.favorites.title, systemImage: RootTab.favorites.symbol, value: RootTab.favorites) {
                FavoritesTabView(navigation: favorites, reader: readerServices(), composer: nil)
            }
        }
        // The app's default (`tabbar_minimize_on_scroll` is on).
        .tabBarMinimizeBehavior(.onScrollDown)
        .environment(ExperimentalSettings(store: InMemorySettingsStore()))
        .environment(makeModel(store: InMemoryCredentialStore()))
        .appTypography(.standard, density: density)
        let scene = try #require(UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.screen.bounds
        window.rootViewController = UIHostingController(rootView: root)
        window.isHidden = false
        return HostedCategoriesTab(window: window, navigation: navigation, data: data)
    }

    /// The category list's scroll view: the tallest scrollable content on screen.
    private func categoryList(in window: UIWindow) -> UIScrollView? {
        HostedAccessibility.elements(under: window)
            .compactMap { $0 as? UIScrollView }
            .filter { $0.contentSize.height > $0.bounds.height }
            .max { $0.contentSize.height < $1.contentSize.height }
    }

    /// The index path of the visible row whose accessibility label starts with `label`.
    private func rowIndexPath(_ label: String, in collection: UICollectionView) -> IndexPath? {
        collection.visibleCells.first { cell in
            HostedAccessibility.elements(under: cell).contains { $0.accessibilityLabel?.hasPrefix(label) == true }
        }
        .flatMap { collection.indexPath(for: $0) }
    }

    /// One layout frame, with a beat for the watchdog.
    private func frame(_ window: UIWindow, _ log: HostedHangWatchdog) async throws {
        try await Task.sleep(for: .milliseconds(50))
        window.layoutIfNeeded()
        log.heartbeat()
    }

    @Test(
        "A category opens without freezing after the list was scrolled (#681)",
        .timeLimit(.minutes(1)), arguments: [ListDensity.regular, .compact], [true, false]
    )
    func aCategoryOpensAfterAScroll(density: ListDensity, scrolled: Bool) async throws {
        let log = HostedHangWatchdog(tag: "#681")
        log.watch(limit: 45)
        HostedAccessibility.setAutomation(true)
        defer {
            HostedAccessibility.setAutomation(false)
            log.stop()
        }
        let name = "\(density) scrolled=\(scrolled)"
        log.mark("\(name): setup")
        let hosted = try await hostCategoriesTab(density: density)
        let (window, navigation, data) = (hosted.window, hosted.navigation, hosted.data)
        defer { window.isHidden = true }
        let traits = window.traitCollection
        log.mark(
            "\(name): window \(window.bounds.size), safe area \(window.safeAreaInsets), "
                + "size classes h=\(traits.horizontalSizeClass.rawValue) v=\(traits.verticalSizeClass.rawValue), "
                + "model \(UIDevice.current.model)"
        )

        var list: UIScrollView?
        for _ in 0..<100 where list == nil {
            try await frame(window, log)
            list = categoryList(in: window)
        }
        let scrollView = try #require(list, "the category list is not on screen")
        if scrolled {
            // In steps, as a finger would: the large title row leaves the screen on the way and the pill takes over. The end is
            // read again at each step, as the list sizes its rows as they come.
            for _ in 0..<60 {
                let end = scrollView.contentSize.height - scrollView.bounds.height + scrollView.adjustedContentInset.bottom
                if scrollView.contentOffset.y >= end - 0.5 { break }
                let y = min(scrollView.contentOffset.y + scrollView.bounds.height / 4, end)
                scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: y), animated: false)
                try await frame(window, log)
            }
            log.mark("\(name): scrolled to y=\(scrollView.contentOffset.y) of \(scrollView.contentSize.height)")
        }

        let label = scrolled ? "Catégorie \(Self.lastCategory)" : "Catégorie 13"
        let collection = try #require(scrollView as? UICollectionView, "the category list is not a collection view")
        var row: IndexPath?
        for _ in 0..<40 where row == nil {
            try await frame(window, log)
            row = rowIndexPath(label, in: collection)
        }
        let indexPath = try #require(row, "the row of \(label) is not on screen")

        // What UIKit does for a tap on a row: SwiftUI's list writes its selection from the collection view's delegate.
        log.mark("\(name): selecting '\(label)' at \(indexPath)")
        collection.selectItem(at: indexPath, animated: false, scrollPosition: [])
        collection.delegate?.collectionView?(collection, didSelectItemAt: indexPath)
        log.mark("\(name): selected")
        let category = scrolled ? Self.lastCategory : 13
        for _ in 0..<100 where !data.requests.contains(where: { $0.hasPrefix("topics:\(category):") }) {
            try await frame(window, log)
        }
        // A push loop shows once the push has settled, over the scrolled list: give it frames.
        for index in 0..<20 {
            try await frame(window, log)
            log.mark("\(name): frame \(index) after the push")
        }
        #expect(navigation.selectedSource == .forum(.forum(category), title: "Catégorie \(category)"))
        #expect(data.requests.contains("topics:\(category):1"), "\(data.requests)")
    }
}
