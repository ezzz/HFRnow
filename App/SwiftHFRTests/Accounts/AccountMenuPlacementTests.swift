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

    @Test func placementIsLeading() {
        #expect(AccountMenuButton.placement == .topBarLeading)
    }

    /// Hosts a root in a navigation controller, as the tabs do, and reads the UIKit bar items SwiftUI builds from its toolbar.
    @Test func modifierPutsTheItemOnTheLeftOfTheBarOnly() async throws {
        let scene = try #require(UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene)
        let root = Text("Racine").accountMenuToolbarItem().environment(AccountsModel.preview())
        let host = UIHostingController(rootView: NavigationStack { root })
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        var bar: UINavigationBar?
        for _ in 0..<100 {
            try? await Task.sleep(for: .milliseconds(50))
            window.layoutIfNeeded()
            bar = Self.navigationBar(in: host.view)
            if let items = bar?.topItem, !(items.leftBarButtonItems ?? []).isEmpty { break }
        }
        let item = try #require(bar?.topItem)
        #expect(!(item.leftBarButtonItems ?? []).isEmpty)
        #expect((item.rightBarButtonItems ?? []).isEmpty)
    }

    private static func navigationBar(in view: UIView) -> UINavigationBar? {
        if let bar = view as? UINavigationBar { return bar }
        return view.subviews.lazy.compactMap { navigationBar(in: $0) }.first
    }
}
