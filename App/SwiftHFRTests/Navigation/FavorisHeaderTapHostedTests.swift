import Foundation
import HFRModels
import HFRNetwork
import HFRStorage
@testable import SwiftHFR
import SwiftUI
import Testing
import UIKit

/// The hosted Favoris tab and the models a test checks.
private struct HostedFavoritesTab {
    let window: UIWindow
    let navigation: NavigationModel
    let filter: TopicFilterModel
    let data: FakeDataSource
}

/// #979: a tap on a Favoris section title froze the app in compact density. The Favoris tab as `RootTabsView` builds it (tab
/// view, collapsed split view, Catégories beside it on the same filter and forum list), signed in, sectioned by category, at
/// iPhone widths; the title is activated through the accessibility element of the button the header draws.
///
/// The freeze: once the category was pushed, the Favoris list sat under it, moved by the push's parallax. The section headers
/// measured that move as their own misplacement and padded themselves by it, past their content on a narrow screen, which moved
/// what they measured: an endless measure-and-pad loop on the main thread (`DensityHeaderMargin`).
@MainActor
@Suite(.serialized)
struct FavorisHeaderTapHostedTests {
    private func readerServices() -> ReaderServices {
        ReaderServices(
            imageFetcher: ReaderImageFetcher(transport: MockTransport(replies: [])),
            settings: ReaderSettings(
                autoLoadsThirdPartyImages: { false }, renderOptions: { ReaderRenderOptions() }, swipesPages: { false }
            ),
            profiles: FakeUserProfiles([])
        )
    }

    /// The favourites page (15 categories of 6 topics) and the forum list (the same categories, 8 sub-forums each).
    private func dataSource() -> FakeDataSource {
        let data = FakeDataSource()
        data.favoritesHandler = { _ in
            FavoritesPage(sections: (13..<28).map { category in
                favoriteSection(category, (0..<6).map { favoriteTopic(category * 100 + $0, category: category) })
            })
        }
        data.forumHandler = {
            ForumListPage(forums: (13..<28).map { category in
                ForumCategory(
                    categoryID: .forum(category), title: "Catégorie \(category)", path: "/c\(category)",
                    subforums: (1...8).map { ForumLink(title: "Sous-forum \($0)", path: "/c\(category)/s\($0)") }
                )
            }, isLoggedIn: true)
        }
        return data
    }

    /// The Favoris tab, with Catégories beside it, hosted in a `width` window as the app builds it.
    private func hostFavoritesTab(density: ListDensity, width: CGFloat) async throws -> HostedFavoritesTab {
        let data = dataSource()
        let store = InMemorySettingsStore()
        let options = favoritesOptions(settings: store)
        options.groupedByCategory = true
        let filter = TopicFilterModel(settings: store)
        let forums = ForumListModel(dataSource: data)
        let navigation = NavigationModel(
            dataSource: data, forums: forums, sessionIsLoggedIn: { true }, startupSource: .favorites, favorites: options,
            topicFilter: filter
        )
        let categories = NavigationModel(dataSource: data, forums: forums, sessionIsLoggedIn: { true }, topicFilter: filter)
        await forums.loadIfNeeded()
        // The operator's setup: the dense rows' bold section titles (#905 F).
        let experimental = ExperimentalSettings(store: InMemorySettingsStore())
        experimental.set(.denseRows, isOn: true)
        let root = TabView(selection: .constant(RootTab.favorites)) {
            Tab(RootTab.categories.title, systemImage: RootTab.categories.symbol, value: RootTab.categories) {
                CategoriesTabView(navigation: categories, reader: readerServices(), composer: nil)
            }
            Tab(RootTab.favorites.title, systemImage: RootTab.favorites.symbol, value: RootTab.favorites) {
                FavoritesTabView(navigation: navigation, reader: readerServices(), composer: nil)
            }
        }
        .environment(experimental)
        .environment(makeModel(store: InMemoryCredentialStore()))
        .appTypography(.standard, density: density)
        let scene = try #require(UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: width, height: 874)
        window.rootViewController = UIHostingController(rootView: root)
        window.isHidden = false
        return HostedFavoritesTab(window: window, navigation: navigation, filter: filter, data: data)
    }

    @Test(
        "A section title pushes its category without freezing (#979)",
        .timeLimit(.minutes(1)), arguments: [ListDensity.compact, .regular], [CGFloat(320), 402]
    )
    func aSectionTitlePushesItsCategory(density: ListDensity, width: CGFloat) async throws {
        let log = HostedHangWatchdog(tag: "#979")
        log.watch(limit: 45)
        HostedAccessibility.beginAutomation()
        defer {
            HostedAccessibility.endAutomation()
            log.stop()
        }
        log.mark("\(density) \(width): setup")
        let hosted = try await hostFavoritesTab(density: density, width: width)
        let (window, navigation, filter, data) = (hosted.window, hosted.navigation, hosted.filter, hosted.data)
        defer { window.isHidden = true }

        var title: NSObject?
        for _ in 0..<100 where title == nil {
            try await Task.sleep(for: .milliseconds(50))
            window.layoutIfNeeded()
            log.heartbeat()
            title = HostedAccessibility.elements(under: window).first {
                $0.accessibilityLabel == "Catégorie 13" && $0.accessibilityHint == "Ouvrir le forum"
            }
        }
        let element = try #require(title, "the section title is not on screen")

        log.mark("\(density) \(width): tapping the section title")
        #expect(element.accessibilityActivate())
        log.mark("\(density) \(width): tapped")
        for _ in 0..<100 where !data.requests.contains(where: { $0.hasPrefix("topics:13:") }) {
            try await Task.sleep(for: .milliseconds(50))
            window.layoutIfNeeded()
            log.heartbeat()
        }
        // The freeze came once the push had settled, the Favoris list under the category: give it frames to show.
        for frame in 0..<20 {
            try await Task.sleep(for: .milliseconds(50))
            window.layoutIfNeeded()
            log.mark("\(density) \(width): frame \(frame) after the push")
        }
        #expect(navigation.openedCategory == .forum(.forum(13), title: "Catégorie 13"))
        #expect(filter.flag == .favorites)
        #expect(data.requests.contains("topics:13:1:owntopic=\(TopicListFilter.favorites.rawValue)"), "\(data.requests)")
    }
}
