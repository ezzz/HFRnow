import HFRModels
import HFRNetwork
import HFRStorage
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

    /// The detail column's own UIKit view, to ask the window whether that column is drawn. SwiftUI's `onAppear` does not
    /// tell: in the collapsed split it fires for a detail whose view is never created (measured on the Mac, iOS 27.0
    /// simulator, #431: phone rule, one view controller in the split, the marker never in the window; iPad rule, the marker in
    /// the window at (601, 231)).
    private final class DetailMarker: UIView {}

    /// Puts a `DetailMarker` in the detail column and hands it to `found`.
    private struct Marker: UIViewRepresentable {
        let found: Found

        func makeUIView(context: Context) -> DetailMarker {
            let view = DetailMarker()
            found.add(view)
            return view
        }

        func updateUIView(_ uiView: DetailMarker, context: Context) {}
    }

    /// Every marker SwiftUI made, held weakly: a detail made again must not hide an earlier one still drawn.
    @MainActor
    private final class Found {
        private final class Weak {
            weak var marker: DetailMarker?

            init(_ marker: DetailMarker) { self.marker = marker }
        }

        private var markers: [Weak] = []

        func add(_ marker: DetailMarker) {
            markers.append(Weak(marker))
        }

        /// Whether the detail column is drawn in `window` now: one of its markers is in that window, with no hidden or
        /// transparent ancestor, and overlaps the window's bounds.
        func detailOnScreen(in window: UIWindow) -> Bool {
            markers.contains { entry in
                guard let marker = entry.marker, marker.window === window else { return false }
                var view: UIView? = marker
                while let current = view {
                    if current.isHidden || current.alpha == 0 { return false }
                    view = current.superview
                }
                return marker.convert(marker.bounds, to: nil).intersects(window.bounds)
            }
        }
    }

    /// A split built as the tabs build theirs: a list and a detail, showing the list when collapsed.
    private struct Probe: View {
        let found: Found

        var body: some View {
            NavigationSplitView(preferredCompactColumn: .constant(.sidebar)) {
                Text("Liste")
            } detail: {
                Marker(found: found).frame(width: 50, height: 50)
            }
            .modifier(TabSplitWidth())
        }
    }

    /// The tabs whose own split view applies `TabSplitWidth`.
    enum TabRoot: Sendable, CaseIterable { case categories, favorites, messages }

    private func splitViews(in controller: UIViewController) -> [UISplitViewController] {
        let own = (controller as? UISplitViewController).map { [$0] } ?? []
        return own + controller.children.flatMap { splitViews(in: $0) }
    }

    /// `root` in a Pro Max-in-landscape window (932 × 430, regular width, compact height), deciding for `idiom`. The accounts
    /// model is there as `RootView` puts it: the Catégories list's account button reads it, and SwiftUI traps without it.
    private func hostInLandscape<Root: View>(_ root: Root, idiom: UIUserInterfaceIdiom) throws -> (UIWindow, UIViewController) {
        let accounts = makeModel(store: InMemoryCredentialStore())
        let host = UIHostingController(rootView: root.environment(\.tabSplitIdiom, idiom).environment(accounts))
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

    /// On a phone the split collapses and, once settled, its detail column is not on screen beside the list. The same window
    /// with the iPad rule shows both columns, so the window really is regular width. (The list's own width class tells
    /// nothing: UIKit hands a split's side column a compact width whatever the split's.)
    @Test(arguments: [UIUserInterfaceIdiom.phone, .pad])
    func theTabSplitCollapsesOnALandscapePhoneOnly(idiom: UIUserInterfaceIdiom) async throws {
        let found = Found()
        let (window, host) = try hostInLandscape(Probe(found: found), idiom: idiom)
        defer { window.isHidden = true }
        for _ in 0..<100 where idiom == .pad && !found.detailOnScreen(in: window) {
            try await Task.sleep(for: .milliseconds(20))
            window.layoutIfNeeded()
        }
        let splits = try await settledSplits(in: host, window: window)
        #expect(!splits.isEmpty)
        if idiom == .phone {
            #expect(!found.detailOnScreen(in: window), "the reader's column is on screen beside the list")
            #expect(splits.allSatisfy { $0.isCollapsed }, "collapsed: \(splits.map { $0.isCollapsed })")
        } else {
            #expect(found.detailOnScreen(in: window), "the detail column is not on screen: the window is not regular width")
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
