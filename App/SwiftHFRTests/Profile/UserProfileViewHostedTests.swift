import HFRNetwork
@testable import SwiftHFR
import SwiftUI
import Testing
import UIKit

/// The real `UserProfileView` in a window. Issue #1312 (operator, 2026-11-28): legacy's profile has no pull to refresh, so the
/// list carries no refresh control; the toolbar's « Actualiser » and the error's « Réessayer » stay the ways to reload.
@MainActor
struct UserProfileViewHostedTests {
    private func scrollViews(in view: UIView) -> [UIScrollView] {
        var found = (view as? UIScrollView).map { [$0] } ?? []
        for child in view.subviews { found += scrollViews(in: child) }
        return found
    }

    @Test func theProfileListHasNoPullToRefresh() async throws {
        let profile = try UserProfileModelTests.captured("R56a-profile-operator-anon.html")
        let model = UserProfileModel(memberID: 910_001, source: FakeUserProfiles([.success(profile)]))
        let services = ReaderServices(
            imageFetcher: ReaderImageFetcher(transport: MockTransport(replies: [])),
            settings: ReaderSettings(
                autoLoadsThirdPartyImages: { false }, renderOptions: { ReaderRenderOptions() }, swipesPages: { false }
            ),
            profiles: FakeUserProfiles([])
        )
        let controller = UIHostingController(rootView: UserProfileView(model: model, services: services))
        let scene = try #require(UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        for _ in 0..<100 where model.profile == nil || scrollViews(in: controller.view).isEmpty {
            controller.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
        }
        controller.view.layoutIfNeeded()
        let lists = scrollViews(in: controller.view)
        #expect(model.profile != nil)
        #expect(!lists.isEmpty)
        #expect(lists.allSatisfy { $0.refreshControl == nil })
    }
}
