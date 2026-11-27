import Foundation
import HFRClient
import HFRModels
import HFRNetwork
import HFRStorage
@testable import SwiftHFR
import Testing

/// LOT-159 R1: one review-account configuration (Q-7). The root the app builds (`RootModel(environment:store:)`) hands the
/// environment's `ForumVisibility` to the forum list, to the search picker (through the forum list) and to the AQ list, so a
/// review account named elsewhere than `applereview` is applied by all three. A model that builds its own default
/// configuration instead fails one expectation.
@MainActor
struct ReviewAccountConfigurationTests {
    private static let reviewer = "fakereviewer"

    nonisolated private static let page = ForumListPage(
        forums: [
            ForumCategory(categoryID: .forum(13), title: "Discussions", path: "/hfr/Discussions/liste_sujet-1.htm"),
            ForumCategory(categoryID: .forum(25), title: "Apple", path: "/hfr/apple/liste_sujet-1.htm")
        ],
        isLoggedIn: true
    )

    /// The app's root for `account`, logged in, with the review account configured as `reviewer`.
    private func root(account: String, items: [AQFeedItem]) -> RootModel {
        let data = FakeDataSource()
        data.forumHandler = { Self.page }
        let live = AppEnvironment.make(session: HFRSession(), accountName: nil)
        var environment = AppEnvironment(
            session: HFRSession(cookies: Fake.cookies(user: account), hashCheck: "fake-hash"), dataSource: data,
            visibility: ForumVisibility(reviewAccountName: Self.reviewer), currentAccountName: account,
            topicPages: FakeTopicPages(), reader: live.reader, privateMessages: FakePrivateMessages(), composer: nil,
            filteredPosts: live.filteredPosts, favoriteStores: live.favoriteStores, flagActions: nil, memberAvatars: nil,
            pseudoListsSnapshot: live.pseudoListsSnapshot, blocklistChanges: nil, privateMessageCount: nil
        )
        environment.qualityAlertsSource = FakeQualityAlertsSource(items: items)
        return RootModel(environment: environment, store: InMemorySettingsStore())
    }

    private func feed() throws -> (items: [AQFeedItem], forum25: AQFeedItem) {
        let items = try QualityAlertsTestSupport.capturedItems()
        let forum25 = try QualityAlertsTestSupport.inForum25(items[0])
        return (items + [forum25], forum25)
    }

    @Test func theConfiguredReviewAccountSeesNoAppleCategoryAnywhere() async throws {
        let (items, forum25) = try feed()
        let root = root(account: Self.reviewer, items: items)
        await root.forums.loadIfNeeded()
        #expect(root.forums.loader.value?.sections.map(\.title) == ["Discussions"], "forum list")
        root.search.setCategories(from: root.forums.loader.value)
        #expect(root.search.categories.map(\.id) == [.forum(13)], "search picker")
        await root.qualityAlerts.load()
        #expect(!root.qualityAlerts.rows.isEmpty)
        #expect(!root.qualityAlerts.rows.contains { $0.item.link == forum25.link }, "AQ list")
    }

    @Test func anotherAccountSeesItEverywhere() async throws {
        let (items, forum25) = try feed()
        let root = root(account: "fakemember", items: items)
        await root.forums.loadIfNeeded()
        #expect(root.forums.loader.value?.sections.map(\.title) == ["Discussions", "Apple"])
        root.search.setCategories(from: root.forums.loader.value)
        #expect(root.search.categories.map(\.id) == [.forum(13), .forum(25)])
        await root.qualityAlerts.load()
        #expect(root.qualityAlerts.rows.contains { $0.item.link == forum25.link })
    }
}
