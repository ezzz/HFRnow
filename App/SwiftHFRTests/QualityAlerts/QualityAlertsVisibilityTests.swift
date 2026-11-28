import Foundation
import HFRClient
import HFRModels
import HFRStorage
@testable import SwiftHFR
import Testing

/// Category 25 (Apple) is hidden when logged out and for the review account, in the list and in the count (Q-7).
@MainActor
struct QualityAlertsVisibilityTests {
    typealias Support = QualityAlertsTestSupport

    /// The captured feed plus one item of its own raised in forum 25 (derived: see `inForum25`).
    private func feed() throws -> (items: [AQFeedItem], forum25: AQFeedItem) {
        let items = try Support.capturedItems()
        let forum25 = try Support.inForum25(items[0])
        return (items + [forum25], forum25)
    }

    @Test(arguments: [(nil as String?, false), ("applereview", true), ("AppleReview", true)])
    func forum25IsHiddenForTheLoggedOutAndTheReviewAccount(account: String?, loggedIn: Bool) async throws {
        let (items, forum25) = try feed()
        let model = Support.model(source: FakeQualityAlertsSource(items: items), accountName: account, isLoggedIn: loggedIn)
        await model.refreshCount()
        #expect(model.unreadCount == 25)
        await model.load()
        #expect(model.rows.count == 25)
        #expect(!model.rows.contains { $0.item.link == forum25.link })
    }

    @Test func forum25ShowsForAnotherAccountAndIsCounted() async throws {
        let (items, forum25) = try feed()
        let model = Support.model(source: FakeQualityAlertsSource(items: items), accountName: "member", isLoggedIn: true)
        await model.refreshCount()
        #expect(model.unreadCount == 26)
        await model.load()
        #expect(model.rows.contains { $0.item.link == forum25.link })
    }

    /// #1398: a root rebuilt on an account switch counts from the feed the first root read, with the new viewer's rule: the review
    /// account's root hides forum 25, another account's counts it, and no request leaves.
    @Test func aRebuiltRootAppliesTheNewViewersRuleToTheFeedAlreadyRead() async throws {
        let (items, _) = try feed()
        let source = FakeQualityAlertsSource(items: items)
        let launchFeed = QualityAlertsLaunchFeed()
        let member = Support.model(source: source, accountName: "member", isLoggedIn: true, launchFeed: launchFeed)
        await member.checkAtLaunch(sleep: { _ in })
        #expect(member.unreadCount == 26)
        let reviewer = Support.model(source: source, accountName: "applereview", isLoggedIn: true, launchFeed: launchFeed)
        await reviewer.checkAtLaunch(sleep: { _ in })
        #expect(reviewer.unreadCount == 25)
        let loggedOut = Support.model(source: source, launchFeed: launchFeed)
        await loggedOut.checkAtLaunch(sleep: { _ in })
        #expect(loggedOut.unreadCount == 25)
        #expect(source.calls == 1)
    }

    @Test func aLoggedInSessionThatExpiredReadsAsLoggedOut() async throws {
        let (items, _) = try feed()
        let model = Support.model(source: FakeQualityAlertsSource(items: items), accountName: "member", isLoggedIn: false)
        await model.refreshCount()
        #expect(model.unreadCount == 25)
    }

    @Test func linksWithoutACategoryStayVisible() async throws {
        let items = try Support.capturedItems()
        let canonical = items.filter { QualityAlertsModel.category(of: $0.link) == nil }
        // `T01`: two of the 25 links are canonical `…-sujet_N_P.htm` paths (HFR-PROTOCOL §6c LOT-028).
        #expect(canonical.count == 2)
        let model = Support.model(source: FakeQualityAlertsSource(items: items))
        await model.load()
        #expect(model.rows.count == 25)
    }
}
