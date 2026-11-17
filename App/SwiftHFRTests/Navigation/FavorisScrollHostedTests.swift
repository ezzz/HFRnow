import HFRModels
import SwiftUI
@testable import SwiftHFR
import Testing
import UIKit

/// The first scroll of Favoris (#1015): the large title leaving and coming back, and the bars moving, must not run the list's body.
/// Each run re-applies the modifiers of every realised row and every section header, a cost that grows with the sections and rows.
@MainActor
@Suite(.serialized)
struct FavorisScrollHostedTests {
    /// Favoris with ten categories of eight topics, loaded.
    private func favorites() async -> NavigationModel {
        let data = FakeDataSource()
        data.favoritesHandler = { _ in
            FavoritesPage(sections: (1...10).map { category in
                favoriteSection(category, (1...8).map { favoriteTopic(category * 100 + $0, category: category, day: $0) })
            })
        }
        let navigation = NavigationModel(dataSource: data, startupSource: .favorites, favorites: favoritesOptions())
        await navigation.topicList(for: .favorites).loadIfNeeded()
        return navigation
    }

    private static func collectionView(in view: UIView) -> UICollectionView? {
        if let collection = view as? UICollectionView { return collection }
        return view.subviews.lazy.compactMap { collectionView(in: $0) }.first
    }

    /// The large title is the only row of the list's first section.
    private static func showsLargeTitle(_ list: UICollectionView) -> Bool {
        list.indexPathsForVisibleItems.contains(IndexPath(item: 0, section: 0))
    }

    private static func settle() async {
        try? await Task.sleep(for: .milliseconds(17))
    }

    @Test("Scrolling Favoris across its large title, and the bars moving, never run the list's body")
    func scrollLeavesTheListAlone() async throws {
        let navigation = await favorites()
        let model = navigation.topicList(for: .favorites)
        let key = ObjectIdentifier(model)
        let scene = try #require(UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        // The Favoris tab as `FavoritesTabView` builds it, under a tab bar that minimises on scroll.
        let host = UIHostingController(rootView: TabView(selection: .constant(0)) {
            Tab("Favoris", systemImage: "star", value: 0) {
                NavigationSplitView {
                    TopicsColumn(navigation: navigation, composer: nil).appScreenBackground()
                } detail: {
                    Text("Lecteur")
                }
            }
            Tab("Messages", systemImage: "envelope", value: 1) { Text("Messages") }
        }
        .tabBarMinimizeBehavior(.onScrollDown))
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        var found: UICollectionView?
        for _ in 0..<100 {
            await Self.settle()
            window.layoutIfNeeded()
            found = Self.collectionView(in: window)
            if let found, found.visibleCells.count > 5 { break }
        }
        let list = try #require(found)
        try? await Task.sleep(for: .milliseconds(300))
        let landed = TopicListView.bodyRuns[key] ?? 0
        #expect(landed > 0, "the seam counts this list")
        #expect(Self.showsLargeTitle(list))

        // Down past the large title, one frame at a time, then the bars moving, then back to the top.
        let top = list.contentOffset.y
        for step in 1...60 {
            list.setContentOffset(CGPoint(x: 0, y: top + CGFloat(step) * 5), animated: false)
            await Self.settle()
        }
        #expect(!Self.showsLargeTitle(list), "the large title has left the screen")
        for step in [8, 16, 24, 32, 24, 16, 8, 0] {
            host.additionalSafeAreaInsets = UIEdgeInsets(top: CGFloat(step) / 2, left: 0, bottom: CGFloat(step), right: 0)
            await Self.settle()
        }
        for step in stride(from: 59, through: 0, by: -1) {
            list.setContentOffset(CGPoint(x: 0, y: top + CGFloat(step) * 5), animated: false)
            await Self.settle()
        }
        #expect(Self.showsLargeTitle(list), "the large title is back")
        #expect((TopicListView.bodyRuns[key] ?? 0) == landed, "body runs during the scroll: \((TopicListView.bodyRuns[key] ?? 0) - landed)")
    }
}
