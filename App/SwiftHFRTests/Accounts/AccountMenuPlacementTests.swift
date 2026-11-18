import HFRModels
import HFRNetwork
import HFRStorage
@testable import SwiftHFR
import SwiftUI
import Testing
import UIKit

/// The account button of the main roots (#1057): leading, with the avatar as label.
@MainActor
@Suite(.serialized)
struct AccountMenuPlacementTests {
    @Test func labelIsTheAvatarWhenTheAccountHasOne() {
        #expect(AccountMenuLabelContent.content(hasAvatar: true, status: .valid) == .avatar)
        #expect(AccountMenuLabelContent.content(hasAvatar: true, status: .restored) == .avatar)
    }

    @Test func labelFallsBackToThePersonSymbolWithoutAvatar() {
        #expect(AccountMenuLabelContent.content(hasAvatar: false, status: .valid) == .symbol("person.crop.circle.fill"))
        #expect(AccountMenuLabelContent.content(hasAvatar: false, status: nil) == .symbol("person.crop.circle.fill"))
    }

    @Test func expiredSessionKeepsTheBadgeEvenWithAnAvatar() {
        let badge = AccountMenuLabelContent.symbol("person.crop.circle.badge.exclamationmark")
        #expect(AccountMenuLabelContent.content(hasAvatar: true, status: .expired) == badge)
        #expect(AccountMenuLabelContent.content(hasAvatar: false, status: .expired) == badge)
    }

    /// What the window's top bars show on their left, and everything seen, for a failure message.
    private struct Found {
        /// Items SwiftUI handed the bar on its left (`leftBarButtonItems` and leading item groups).
        var leftItems = 0
        /// Visible controls drawn in the left half of a bar.
        var leftControls = 0
        /// Bars, item counts and control classes seen, whatever the outcome.
        var diagnostics = ""
        var isOnTheLeft: Bool { leftItems > 0 || leftControls > 0 }
    }

    /// Hosts `root` in a window as a tab does and reads its top bars: the items SwiftUI gave the navigation item on the left
    /// and the controls drawn in the left half of a bar (SwiftUI may fill leading item groups instead of `leftBarButtonItems`,
    /// and its bar buttons are controls whose accessibility label a unit-test run does not reliably expose, so neither source
    /// is trusted alone). The roots have no back button and no other leading item, so without the modifier both stay empty.
    private func readBars(of root: some View) async throws -> Found {
        let scene = try #require(UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene)
        let host = UIHostingController(rootView: root.environment(AccountsModel.preview()))
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        var found = Found()
        for _ in 0..<100 {
            try? await Task.sleep(for: .milliseconds(50))
            window.layoutIfNeeded()
            found = Self.read(window)
            if found.isOnTheLeft { break }
        }
        return found
    }

    private static func read(_ window: UIWindow) -> Found {
        var found = Found()
        let bars = views(in: window).compactMap { $0 as? UINavigationBar }.filter { !$0.isHidden && $0.alpha > 0 }
        found.diagnostics = "\(bars.count) bar(s)"
        for bar in bars {
            let item = bar.topItem
            let left = (item?.leftBarButtonItems ?? []).count + (item?.leadingItemGroups ?? []).flatMap(\.barButtonItems).count
            let right = (item?.rightBarButtonItems ?? []).count + (item?.trailingItemGroups ?? []).flatMap(\.barButtonItems).count
            // Shown: in the window, with no hidden or transparent view between it and the bar (UIKit keeps unused back buttons and
            // transition copies around with alpha 0). Disabled controls count: the preview "Comptes" button is disabled.
            let controls = views(in: bar).compactMap { $0 as? UIControl }.filter { isShown($0, below: bar) && !$0.bounds.isEmpty }
            let onTheLeft = controls.filter { bar.convert($0.bounds, from: $0).midX < bar.bounds.midX }
            found.leftItems += left
            found.leftControls += onTheLeft.count
            let leftTitles = ((item?.leftBarButtonItems ?? []) + (item?.leadingItemGroups ?? []).flatMap(\.barButtonItems))
                .map { (entry: UIBarButtonItem) -> String in
                    if let title = entry.title ?? entry.accessibilityLabel { return title }
                    return entry.customView.map { String(describing: type(of: $0)) } ?? "item"
                }
            found.diagnostics += "; left items \(leftTitles); bar \(bar.bounds.size): items left \(left) right \(right), controls "
                + controls.map { "\(type(of: $0))@\(Int(bar.convert($0.bounds, from: $0).midX))" }.joined(separator: ",")
        }
        return found
    }

    private static func isShown(_ view: UIView, below bar: UIView) -> Bool {
        guard view.window != nil else { return false }
        var current: UIView? = view
        while let node = current, node !== bar {
            if node.isHidden || node.alpha <= 0.01 { return false }
            current = node.superview
        }
        return current === bar
    }

    private func expectOnTheLeft(_ found: Found, _ name: String) {
        // Always recorded: a pass, trivial or real, then shows what satisfied it.
        print("AccountMenuPlacementTests \(name): \(found.diagnostics)")
        #expect(found.isOnTheLeft, "\(name): nothing on the left of the bar: \(found.diagnostics)")
    }

    private func services() -> ReaderServices {
        ReaderServices(
            imageFetcher: ReaderImageFetcher(transport: MockTransport(replies: [])),
            settings: ReaderSettings(
                autoLoadsThirdPartyImages: { false }, renderOptions: { ReaderRenderOptions() }, swipesPages: { false }
            ),
            profiles: FakeUserProfiles([])
        )
    }

    /// The modifier itself: the button is drawn on the left half, in the top bar.
    @Test func modifierDrawsTheButtonOnTheLeftOfTheBar() async throws {
        expectOnTheLeft(try await readBars(of: NavigationStack { Text("Racine").accountMenuToolbarItem() }), "modifier")
    }

    /// Negative controls: the probe tells the cases apart. The pre-fix placement (`.primaryAction`, trailing on an iPhone) and a
    /// root with no account button both read as nothing on the left, so a pass above cannot come from a stray bar item.
    @Test func probeSeesNothingOnTheLeftForTheOldPlacementAndForNoButton() async throws {
        let oldPlacement = try await readBars(of: NavigationStack {
            Text("Racine").toolbar { ToolbarItem(placement: .primaryAction) { AccountMenuButton() } }
        })
        print("AccountMenuPlacementTests old placement: \(oldPlacement.diagnostics)")
        #expect(!oldPlacement.isOnTheLeft, "old placement read as left: \(oldPlacement.diagnostics)")
        let noButton = try await readBars(of: NavigationStack { Text("Racine").navigationTitle("Racine") })
        print("AccountMenuPlacementTests no button: \(noButton.diagnostics)")
        #expect(!noButton.isOnTheLeft, "no button read as left: \(noButton.diagnostics)")
    }

    /// The real roots as `RootTabsView` builds them: removing the modifier from one of them fails here. Not covered: Recherche
    /// (experimental tab) and the iPad sidebar, left to the device check of #893.
    @Test(arguments: ["categories", "favorites", "messages", "plus"])
    func eachMainRootHasTheAccountButtonOnTheLeft(root: String) async throws {
        let reader = services()
        let view: AnyView
        switch root {
        case "categories":
            view = AnyView(CategoriesTabView(navigation: NavigationModel(dataSource: FakeDataSource()), reader: reader, composer: nil))
        case "favorites":
            view = AnyView(FavoritesTabView(
                navigation: NavigationModel(dataSource: FakeDataSource(), startupSource: .favorites), reader: reader, composer: nil
            ))
        case "messages":
            view = AnyView(MessagesRootView(model: MessageListModel(source: FakePrivateMessages()), reader: reader, composer: nil))
        default:
            let data = FakeDataSource()
            let forums = ForumListModel(dataSource: data)
            let model = RootModel(
                forums: forums,
                categories: NavigationModel(dataSource: data, forums: forums, startupSource: RootModel.categoriesStartupSource),
                favorites: NavigationModel(dataSource: data, forums: forums, startupSource: RootModel.favoritesStartupSource),
                messages: MessageListModel(source: FakePrivateMessages()),
                store: InMemorySettingsStore(), initial: nil, privateMessageCount: PrivateMessageCount()
            )
            view = AnyView(NavigationStack { PlusView(model: model) })
        }
        expectOnTheLeft(try await readBars(of: view), root)
    }

    /// A category's topic list is a pushed screen: legacy puts the account button after its back button (`MainWindow.swift:803-818`
    /// @ 87fe0d1c, #425). The back button is no bar item, so a leading item on the pushed screen is the account button; without the
    /// flag the pushed screen has none (negative control, so a pass cannot come from the probe).
    @Test(arguments: [true, false])
    func aPushedCategoryTopicListHasTheAccountButtonOnlyWhenAsked(shows: Bool) async throws {
        let navigation = NavigationModel(dataSource: FakeDataSource())
        let model = navigation.topicList(for: .forum(.forum(13), title: "Matériel"))
        let view = NavigationStack {
            Text("Catégories").navigationDestination(isPresented: .constant(true)) {
                TopicListView(model: model, selection: .constant(nil), showsAccountMenu: shows)
            }
        }
        let found = try await readBars(of: view)
        print("AccountMenuPlacementTests pushed list (\(shows)): \(found.diagnostics)")
        #expect((found.leftItems > 0) == shows, "pushed list, button \(shows): \(found.diagnostics)")
    }

    private static func views(in view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap { views(in: $0) }
    }
}
