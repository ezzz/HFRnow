import HFRModels
import HFRNetwork
@testable import SwiftHFR
import SwiftUI
import Testing
import UIKit

/// Issue #431 (UXD-24): on a large iPhone in landscape (regular width, compact height) the tab root's splits collapse to a
/// stack, so the reader is pushed over the list at full width, as legacy's tab root; an iPad and an iPhone regular in both
/// dimensions keep their width.
@MainActor
@Suite(.serialized)
struct TabSplitWidthTests {
    @Test func aPhoneInLandscapeGivesItsSplitsACompactWidth() {
        #expect(RootNavigationView.tabSplitSizeClass(idiom: .phone, horizontal: .regular, vertical: .compact) == .compact)
        #expect(RootNavigationView.tabSplitSizeClass(idiom: .phone, horizontal: .compact, vertical: .compact) == .compact)
        #expect(RootNavigationView.tabSplitSizeClass(idiom: .phone, horizontal: .compact, vertical: .regular) == .compact)
    }

    @Test func anIPadAndAPhoneRegularInBothDimensionsKeepTheirWidth() {
        #expect(RootNavigationView.tabSplitSizeClass(idiom: .pad, horizontal: .regular, vertical: .compact) == .regular)
        #expect(RootNavigationView.tabSplitSizeClass(idiom: .pad, horizontal: .regular, vertical: .regular) == .regular)
        #expect(RootNavigationView.tabSplitSizeClass(idiom: .pad, horizontal: .compact, vertical: .regular) == .compact)
        #expect(RootNavigationView.tabSplitSizeClass(idiom: .phone, horizontal: .regular, vertical: .regular) == .regular)
    }

    private final class Seen {
        var listWidth: UserInterfaceSizeClass?
        var detailShown = false
    }

    private struct Probe: View {
        let seen: Seen

        var body: some View {
            NavigationSplitView {
                ListSide(seen: seen)
            } detail: {
                Text("Sujet").onAppear { seen.detailShown = true }
            }
            .modifier(TabSplitWidth())
        }
    }

    private struct ListSide: View {
        let seen: Seen
        @Environment(\.horizontalSizeClass) private var width

        var body: some View {
            Text("Liste").onAppear { seen.listWidth = width }
        }
    }

    /// The tabs whose own split view applies `TabSplitWidth`.
    enum TabRoot: Sendable, CaseIterable { case categories, favorites, messages }

    private func splitViews(in controller: UIViewController) -> [UISplitViewController] {
        let own = (controller as? UISplitViewController).map { [$0] } ?? []
        return own + controller.children.flatMap { splitViews(in: $0) }
    }

    /// `root` in a Pro Max-in-landscape window (932 × 430, regular width, compact height), deciding for `idiom`.
    private func hostInLandscape<Root: View>(_ root: Root, idiom: UIUserInterfaceIdiom) throws -> (UIWindow, UIViewController) {
        let host = UIHostingController(rootView: root.environment(\.tabSplitIdiom, idiom))
        host.traitOverrides.horizontalSizeClass = .regular
        host.traitOverrides.verticalSizeClass = .compact
        let scene = try #require(UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 932, height: 430)
        window.rootViewController = host
        window.isHidden = false
        host.view.layoutIfNeeded()
        return (window, host)
    }

    /// Waits for `host`'s split views, then long enough for a detail column to appear beside the list had the split not
    /// collapsed.
    private func settledSplits(in host: UIViewController, window: UIWindow) async throws -> [UISplitViewController] {
        for _ in 0..<100 where splitViews(in: host).isEmpty {
            try await Task.sleep(for: .milliseconds(20))
            window.layoutIfNeeded()
        }
        try await Task.sleep(for: .milliseconds(500))
        window.layoutIfNeeded()
        return splitViews(in: host)
    }

    /// On a phone the split collapses: the list sees a compact width and the detail is not shown beside it. The same window
    /// with the iPad rule shows both columns, so the window really is regular width.
    @Test(arguments: [UIUserInterfaceIdiom.phone, .pad])
    func theTabSplitCollapsesOnALandscapePhoneOnly(idiom: UIUserInterfaceIdiom) async throws {
        let seen = Seen()
        let (window, host) = try hostInLandscape(Probe(seen: seen), idiom: idiom)
        defer { window.isHidden = true }
        for _ in 0..<100 where seen.listWidth == nil || (idiom == .pad && !seen.detailShown) {
            try await Task.sleep(for: .milliseconds(20))
            window.layoutIfNeeded()
        }
        let splits = try await settledSplits(in: host, window: window)
        #expect(!splits.isEmpty)
        if idiom == .phone {
            #expect(seen.listWidth == .compact)
            #expect(!seen.detailShown, "the reader's column is shown beside the list")
            #expect(splits.allSatisfy { $0.isCollapsed }, "collapsed: \(splits.map { $0.isCollapsed })")
        } else {
            #expect(seen.listWidth == .regular)
            #expect(seen.detailShown, "the detail column is not shown: the window is not regular width")
            #expect(splits.allSatisfy { !$0.isCollapsed }, "collapsed: \(splits.map { $0.isCollapsed })")
        }
    }

    /// The real tab views as `RootTabsView` builds them: each one's split collapses in a landscape Pro Max window on a phone,
    /// and stays open with the iPad rule (so removing `TabSplitWidth` from a tab fails here).
    @Test(arguments: TabRoot.allCases, [UIUserInterfaceIdiom.phone, .pad])
    func eachTabsSplitCollapsesOnALandscapePhoneOnly(tab: TabRoot, idiom: UIUserInterfaceIdiom) async throws {
        let services = ReaderServices(
            imageFetcher: ReaderImageFetcher(transport: MockTransport(replies: [])),
            settings: ReaderSettings(
                autoLoadsThirdPartyImages: { false }, renderOptions: { ReaderRenderOptions() }, swipesPages: { false }
            ),
            profiles: FakeUserProfiles([])
        )
        let root: AnyView = switch tab {
        case .categories:
            AnyView(CategoriesTabView(navigation: NavigationModel(dataSource: FakeDataSource()), reader: services, composer: nil))
        case .favorites:
            AnyView(FavoritesTabView(
                navigation: NavigationModel(dataSource: FakeDataSource(), startupSource: .favorites), reader: services, composer: nil
            ))
        case .messages:
            AnyView(MessagesRootView(
                model: MessageListModel(source: FakePrivateMessages()), reader: services, composer: nil
            ))
        }
        let (window, host) = try hostInLandscape(root, idiom: idiom)
        defer { window.isHidden = true }
        let splits = try await settledSplits(in: host, window: window)
        #expect(!splits.isEmpty, "no split view in the \(tab) tab")
        if idiom == .phone {
            #expect(splits.allSatisfy { $0.isCollapsed }, "\(tab): collapsed \(splits.map { $0.isCollapsed })")
        } else {
            #expect(splits.allSatisfy { !$0.isCollapsed }, "\(tab): collapsed \(splits.map { $0.isCollapsed })")
        }
    }
}
