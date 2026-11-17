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

    /// Hosts `root` in a window as a tab does and returns the UIKit bar items SwiftUI built from the toolbars on screen.
    private func barItems(of root: some View) async throws -> (left: Int, right: Int) {
        let scene = try #require(UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene)
        let host = UIHostingController(rootView: root.environment(AccountsModel.preview()))
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        var left = 0
        var right = 0
        for _ in 0..<100 {
            try? await Task.sleep(for: .milliseconds(50))
            window.layoutIfNeeded()
            let items = Self.navigationBars(in: host.view).compactMap(\.topItem)
            left = items.map { ($0.leftBarButtonItems ?? []).count }.reduce(0, +)
            right = items.map { ($0.rightBarButtonItems ?? []).count }.reduce(0, +)
            if left > 0 { break }
        }
        return (left, right)
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

    /// The modifier itself: a left item, no right one.
    @Test func modifierPutsTheItemOnTheLeftOfTheBarOnly() async throws {
        let items = try await barItems(of: NavigationStack { Text("Racine").accountMenuToolbarItem() })
        #expect(items.left > 0)
        #expect(items.right == 0)
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
        let items = try await barItems(of: view)
        #expect(items.left > 0, "\(root): no item on the left of the bar")
    }

    private static func navigationBars(in view: UIView) -> [UINavigationBar] {
        (view as? UINavigationBar).map { [$0] } ?? view.subviews.flatMap { navigationBars(in: $0) }
    }
}
