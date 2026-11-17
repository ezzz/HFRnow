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

    /// Where the account button was drawn, the window's bounds and every accessibility label seen (for a failure message).
    private struct Found {
        let frame: CGRect
        let window: CGRect
        let seen: [String]
    }

    /// Hosts `root` in a window as a tab does and returns where the account button is drawn, in window coordinates, once SwiftUI
    /// has laid its bar out; nil when no view of the window carries the button's label. It reads the rendered button, not the
    /// UIKit bar items: SwiftUI's toolbar does not expose its items there on every iOS version (the first version of this
    /// test read `leftBarButtonItems` and failed on the Mac runner even for the plain modifier).
    private func accountButtonFrame(of root: some View) async throws -> Found? {
        let scene = try #require(UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene)
        let host = UIHostingController(rootView: root.environment(AccountsModel.preview()))
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        var seen: [String] = []
        for _ in 0..<100 {
            try? await Task.sleep(for: .milliseconds(50))
            window.layoutIfNeeded()
            let labelled = Self.views(in: window).filter { $0.window != nil && !$0.isHidden }
            seen = labelled.compactMap { $0.accessibilityLabel }
            // The preview model has not restored its store: the button is the disabled "Comptes" one.
            if let button = labelled.first(where: { $0.accessibilityLabel == "Comptes" }) {
                return Found(frame: button.convert(button.bounds, to: window), window: window.bounds, seen: seen)
            }
        }
        return nil
    }

    private func expectOnTheLeft(_ found: Found?, _ name: String) {
        guard let found else {
            Issue.record("\(name): no view labelled \"Comptes\" in the window")
            return
        }
        #expect(found.frame.midX < found.window.midX, "\(name): button at \(found.frame), window \(found.window), labels \(found.seen)")
        // In the top bar, not in the content: above the first third of the window.
        #expect(found.frame.maxY < found.window.height / 3, "\(name): button at \(found.frame)")
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
        expectOnTheLeft(try await accountButtonFrame(of: NavigationStack { Text("Racine").accountMenuToolbarItem() }), "modifier")
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
        expectOnTheLeft(try await accountButtonFrame(of: view), root)
    }

    private static func views(in view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap { views(in: $0) }
    }
}
