import HFRModels
import HFRNetwork
import HFRStorage
import SwiftUI
@testable import SwiftHFR
import Testing
import UIKit

/// The first scroll of Favoris (#1015): the large title leaving and coming back must not rebuild the list, its section headers or
/// its rows. Each rebuild re-applies the modifiers of every realised row and header, a cost that grows with the sections and rows.
///
/// Covered: the large-title crossings, down and back up, driven frame by frame, and a stand-in for the bars moving (the hosting
/// controller's safe area stepped at the top and bottom). Not covered: the real Liquid Glass tab-bar minimise. A programmatic
/// scroll does not trigger it, and the stand-in is not shown to be what the minimise does to the content; that part is the
/// operator's device check.
@MainActor
@Suite(.serialized)
struct FavorisScrollHostedTests {
    private typealias Part = TopicListView.RenderPart

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

    private func reader() -> ReaderServices {
        ReaderServices(
            imageFetcher: ReaderImageFetcher(transport: MockTransport(replies: [])),
            settings: ReaderSettings(
                autoLoadsThirdPartyImages: { false }, renderOptions: { ReaderRenderOptions() }, swipesPages: { false }
            ),
            profiles: FakeUserProfiles([]), offline: nil
        )
    }

    private static func collectionView(in view: UIView) -> UICollectionView? {
        if let collection = view as? UICollectionView { return collection }
        return view.subviews.lazy.compactMap { collectionView(in: $0) }.first
    }

    private static func settle() async {
        try? await Task.sleep(for: .milliseconds(17))
    }

    /// The parts built since `baseline`, with how many builds each.
    private static func builds(of key: ObjectIdentifier, since baseline: [Part: Int]) -> [Part: Int] {
        (TopicListView.renders[key] ?? [:]).reduce(into: [:]) { result, entry in
            let delta = entry.value - (baseline[entry.key] ?? 0)
            if delta > 0 { result[entry.key] = delta }
        }
    }

    private static func isHeader(_ part: Part) -> Bool {
        if case .header = part { return true }
        return false
    }

    /// A shown window (hide it when done), its hosting controller and the list once it shows rows.
    private struct Hosted {
        let window: UIWindow
        let host: UIViewController
        let list: UICollectionView
    }

    /// The app's Favoris tab under a tab bar that minimises on scroll; the other tabs and the root's environment are left out.
    private func hostFavoris(_ navigation: NavigationModel) async throws -> Hosted {
        let scene = try #require(UIApplication.shared.connectedScenes.first { $0 is UIWindowScene } as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        let host = UIHostingController(rootView: TabView(selection: .constant(0)) {
            Tab("Favoris", systemImage: "star", value: 0) {
                FavoritesTabView(navigation: navigation, reader: reader(), composer: nil)
            }
            Tab("Messages", systemImage: "envelope", value: 1) { Text("Messages") }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        // The tab roots read the accounts model since #1059 (the account button); SwiftUI traps without it.
        .environment(makeModel(store: InMemoryCredentialStore())))
        window.rootViewController = host
        window.isHidden = false
        var found: UICollectionView?
        for _ in 0..<100 {
            await Self.settle()
            window.layoutIfNeeded()
            found = Self.collectionView(in: window)
            if let found, found.visibleCells.count > 5 { break }
        }
        try? await Task.sleep(for: .milliseconds(300))
        return Hosted(window: window, host: host, list: try #require(found))
    }

    /// The rows on screen: section 0 is the large title. Rows built ahead of the screen are built again when they enter it.
    private static func rowsOnScreen(_ list: UICollectionView, groups: [TopicGroup]) -> Set<Part> {
        Set(list.indexPathsForVisibleItems.compactMap { path -> Part? in
            guard path.section > 0, path.section <= groups.count, path.item < groups[path.section - 1].topics.count else { return nil }
            return .row(groups[path.section - 1].topics[path.item].id)
        })
    }

    /// Scrolls `list` to `top` plus 5 pt per step, one frame per step.
    private static func scroll(_ list: UICollectionView, from top: CGFloat, through steps: some Sequence<Int>) async {
        for step in steps {
            list.setContentOffset(CGPoint(x: 0, y: top + CGFloat(step) * 5), animated: false)
            await settle()
        }
    }

    @Test("Scrolling Favoris across its large title rebuilds neither the list, nor a section header, nor a row on screen")
    func scrollLeavesTheListAlone() async throws {
        let navigation = await favorites()
        let key = ObjectIdentifier(navigation.topicList(for: .favorites))
        let hosted = try await hostFavoris(navigation)
        defer { hosted.window.isHidden = true }
        let list = hosted.list
        let baseline = TopicListView.renders[key] ?? [:]
        let visibility = try #require(TopicListView.titleVisibilities[key])
        let landedRows = Self.rowsOnScreen(list, groups: navigation.topicList(for: .favorites).displayedGroups)
        #expect((baseline[.body] ?? 0) > 0, "the seam counts this list")
        #expect(baseline.keys.contains(where: Self.isHeader), "the seam counts its headers")
        #expect(!landedRows.isEmpty && landedRows.allSatisfy { baseline[$0] != nil }, "the seam counts the rows on screen")
        #expect(visibility.isHeaderVisible)

        // Down past the large title, one frame at a time. The rows on screen at landing only leave it: none is built again.
        let top = list.contentOffset.y
        await Self.scroll(list, from: top, through: 1...60)
        let down = Self.builds(of: key, since: baseline)
        #expect(!visibility.isHeaderVisible && visibility.reports >= 1, "the large title has left (reports \(visibility.reports))")
        #expect(down[.body] == nil, "list body runs: \(down[.body] ?? 0)")
        #expect(!down.keys.contains(where: Self.isHeader), "header builds: \(down.filter { Self.isHeader($0.key) })")
        #expect(landedRows.allSatisfy { down[$0] == nil }, "rows built again: \(down.filter { landedRows.contains($0.key) })")

        // The stand-in for the bars moving: nothing in the list is built.
        let beforeBars = TopicListView.renders[key] ?? [:]
        for step in [8, 16, 24, 32, 24, 16, 8, 0] {
            hosted.host.additionalSafeAreaInsets = UIEdgeInsets(top: CGFloat(step) / 2, left: 0, bottom: CGFloat(step), right: 0)
            await Self.settle()
        }
        #expect(Self.builds(of: key, since: beforeBars).isEmpty, "builds: \(Self.builds(of: key, since: beforeBars))")

        // Back up until the large title shows again. Rows coming back on screen are built; the list and the headers are not.
        await Self.scroll(list, from: top, through: stride(from: 59, through: 0, by: -1))
        let round = Self.builds(of: key, since: baseline)
        #expect(visibility.isHeaderVisible && visibility.reports >= 2, "the large title is back (reports \(visibility.reports))")
        #expect(round[.body] == nil, "list body runs: \(round[.body] ?? 0)")
        #expect(!round.keys.contains(where: Self.isHeader), "header builds: \(round.filter { Self.isHeader($0.key) })")
    }
}
