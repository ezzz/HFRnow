import Foundation
import HFRModels
import HFRNetwork
import HFRStorage
@testable import SwiftHFR
import SwiftUI
import Testing
import UIKit

/// #1120 (operator, 2026-11-18): the top bar of every screen sits on Apple's soft scroll-edge effect. Measured on the simulator, the
/// automatic style draws a hard-edged frosted band 116 pt tall under the bar; the soft one fades the content out toward it.
@MainActor
@Suite(.serialized)
struct TopBarEdgeEffectTests {
    nonisolated private static let topics: [TopicSummary] = (1...5).map {
        TopicSummary(topicID: TopicID(category: .forum(23), topic: $0), title: "Sujet \($0)", path: "/t\($0)", readState: .read)
    }

    private func host() throws -> (UIWindow, RootModel) {
        let data = FakeDataSource()
        data.forumHandler = {
            ForumListPage(forums: [
                ForumCategory(categoryID: .forum(23), title: "Apple", path: "/hfr/apple/liste_sujet-1.htm")
            ], isLoggedIn: true)
        }
        data.topicHandler = { _, page in TopicListPage(topics: Self.topics, navigation: PageNavigation(current: page)) }
        data.favoritesHandler = { _ in
            FavoritesPage(sections: [
                FavoriteSection(forum: ForumLink(title: "Apple", path: "/a"), categoryID: .forum(23), topics: Self.topics)
            ])
        }
        let messages = FakePrivateMessages()
        messages.handler = { _ in
            PrivateMessageListPage(threads: [messageThread(12)], navigation: PageNavigation(current: 1, isExact: true))
        }
        let forums = ForumListModel(dataSource: data)
        let model = RootModel(
            forums: forums,
            categories: NavigationModel(dataSource: data, forums: forums, sessionIsLoggedIn: { true }),
            favorites: NavigationModel(
                dataSource: data, forums: forums, sessionIsLoggedIn: { true }, startupSource: .favorites,
                favorites: FavoritesOptionsModel(settings: InMemorySettingsStore())
            ),
            messages: MessageListModel(source: messages, isLoggedIn: { true }), store: InMemorySettingsStore(), initial: .tab(.categories)
        )
        let root = RootTabsView(model: model, environment: AppEnvironment.make(session: HFRSession(), accountName: nil))
            .environment(makeModel(store: InMemoryCredentialStore()))
            .environment(ExperimentalSettings(store: InMemorySettingsStore()))
            .appTypography(.standard, density: .regular)
        let scene = try #require(UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = UIHostingController(rootView: root)
        window.isHidden = false
        return (window, model)
    }

    private static func lists(_ view: UIView) -> [UICollectionView] {
        ((view as? UICollectionView).map { [$0] } ?? []) + view.subviews.flatMap(lists)
    }

    /// The top edge styles of the lists on screen, polled until one shows.
    private func styles(in window: UIWindow) async throws -> [UIScrollEdgeEffect.Style] {
        for _ in 0..<100 {
            try await Task.sleep(for: .milliseconds(50))
            window.layoutIfNeeded()
            let shown = Self.lists(window).filter { !$0.isHidden && $0.window != nil && $0.bounds.width > 300 && $0.numberOfSections > 0 }
            if !shown.isEmpty { return shown.map(\.topEdgeEffect.style) }
        }
        return []
    }

    @Test("Catégories, Favoris, Messages and Plus draw their top edge with the soft effect")
    func everyMainListIsSoft() async throws {
        let (window, model) = try host()
        defer { window.isHidden = true }
        for destination in [SidebarDestination.tab(.categories), .tab(.favorites), .tab(.messages), .tab(.more)] {
            model.selectedDestination = destination
            let found = try await styles(in: window)
            #expect(!found.isEmpty, "\(destination): no list on screen")
            #expect(found.allSatisfy { $0 == .soft }, "\(destination): \(found)")
        }
    }

    @Test("The reader's web view draws its top edge with the soft effect")
    func theReaderIsSoft() {
        let controller = ReaderWebController(
            imageFetcher: ReaderImageFetcher(transport: MockTransport(replies: [])), autoLoadsThirdPartyImages: { false }
        )
        #expect(controller.webView.scrollView.topEdgeEffect.style == .soft)
    }
}
