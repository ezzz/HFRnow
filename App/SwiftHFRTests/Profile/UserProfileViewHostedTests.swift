import HFRNetwork
@testable import SwiftHFR
import SwiftUI
import Testing
import UIKit

/// The real `UserProfileView` in a window. Issue #1312 (operator, 2026-11-28): legacy's profile has no pull to refresh, so the
/// list carries no refresh control; the toolbar's « Actualiser » and the error's « Réessayer » stay the ways to reload.
@MainActor
struct UserProfileViewHostedTests {
    /// The `List`'s own collection view, as `ListDensityLayoutTests` finds it.
    private func collectionView(in view: UIView) -> UICollectionView? {
        if let collection = view as? UICollectionView { return collection }
        return view.subviews.lazy.compactMap { collectionView(in: $0) }.first
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
        for _ in 0..<100 where model.profile == nil || collectionView(in: controller.view) == nil {
            controller.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
        }
        controller.view.layoutIfNeeded()
        #expect(model.profile != nil)
        let list = try #require(collectionView(in: controller.view))
        #expect(list.refreshControl == nil)
    }
}
