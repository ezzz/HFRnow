import HFRModels
import HFRStorage
@testable import SwiftHFR
import SwiftUI
import Testing
import UIKit

/// The top bar of a topic list (#1206): no refresh button (the list refreshes on a pull), « Non lus / Tous » only on Favoris.
@MainActor
@Suite(.serialized)
struct TopicListToolbarTests {
    /// What a window's top bars hold: the items SwiftUI gave the navigation item on each side.
    private struct Bar {
        var leading = 0
        var trailing = 0
        var diagnostics = ""
    }

    private func read(_ window: UIWindow) -> Bar {
        var bar = Bar()
        let bars = Self.views(in: window).compactMap { $0 as? UINavigationBar }.filter { !$0.isHidden && $0.alpha > 0 }
        bar.diagnostics = "\(bars.count) bar(s)"
        for navigationBar in bars {
            let item = navigationBar.topItem
            bar.leading += (item?.leftBarButtonItems ?? []).count + (item?.leadingItemGroups ?? []).flatMap(\.barButtonItems).count
            bar.trailing += (item?.rightBarButtonItems ?? []).count + (item?.trailingItemGroups ?? []).flatMap(\.barButtonItems).count
        }
        bar.diagnostics += "; leading \(bar.leading), trailing \(bar.trailing)"
        return bar
    }

    private static func views(in view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap { views(in: $0) }
    }

    /// Hosts `root` and reads its bar once `ready` holds (the items SwiftUI installs show up a few frames after the window).
    private func bar(of root: some View, ready: (Bar) -> Bool) async throws -> Bar {
        let scene = try #require(UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = UIHostingController(rootView: root.environment(AccountsModel.preview()))
        window.isHidden = false
        defer { window.isHidden = true }
        var found = Bar()
        for _ in 0..<100 {
            try? await Task.sleep(for: .milliseconds(50))
            window.layoutIfNeeded()
            found = read(window)
            if ready(found) { break }
        }
        return found
    }

    /// A category list: the account button (leading) tells the bar is installed; nothing trails. Today the refresh button does.
    @Test func aCategoryListHasNoRefreshButtonInItsBar() async throws {
        let navigation = NavigationModel(dataSource: FakeDataSource())
        let model = navigation.topicList(for: .forum(.forum(13), title: "Matériel"))
        let view = NavigationStack {
            Text("Catégories").navigationDestination(isPresented: .constant(true)) {
                TopicListView(model: model, selection: .constant(nil), showsAccountMenu: true)
            }
        }
        let found = try await bar(of: view, ready: { $0.leading > 0 })
        print("TopicListToolbarTests category: \(found.diagnostics)")
        #expect(found.leading > 0, "the bar was never installed: \(found.diagnostics)")
        #expect(found.trailing == 0, "a category list shows no trailing button without an account to post: \(found.diagnostics)")
    }

    /// Favoris: « Non lus / Tous » is the only trailing item (positive control: the bar did install its trailing group).
    @Test func favorisHasOnlyTheUnreadFilterButtonInItsTrailingGroup() async throws {
        let options = FavoritesOptionsModel(settings: InMemorySettingsStore())
        let navigation = NavigationModel(dataSource: FakeDataSource(), startupSource: .favorites, favorites: options)
        let model = navigation.topicList(for: .favorites)
        let view = NavigationStack { TopicListView(model: model, selection: .constant(nil)) }
        let found = try await bar(of: view, ready: { $0.trailing > 0 })
        print("TopicListToolbarTests favoris: \(found.diagnostics)")
        #expect(found.trailing == 1, "only the unread filter trails on Favoris: \(found.diagnostics)")
    }
}
