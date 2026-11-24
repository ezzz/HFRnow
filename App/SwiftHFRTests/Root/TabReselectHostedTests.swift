import HFRStorage
@testable import SwiftHFR
import Testing
import UIKit

/// The tab bar wiring of the re-selection (#426) on the real root of `DuoLayoutHostedTests`: the tab bar controller's delegate. The
/// sidebar's has no test in CI (#1323); the model's reloads are in `TabReselectTests`.
@MainActor
@Suite(.serialized)
struct TabReselectHostedTests {
    @MainActor
    private final class HapticLog {
        var played: [HapticFeedback.Kind] = []
        var haptics: HapticFeedback { HapticFeedback(store: InMemorySettingsStore()) { self.played.append($0) } }
    }

    /// Records what UIKit asks the delegate SwiftUI installed, and answers `shouldSelectTab` as told.
    @MainActor
    private final class OriginalDelegate: NSObject, UITabBarControllerDelegate {
        var answer = true
        var shouldSelectCalls = 0
        var didSelectCalls = 0

        func tabBarController(_ tabBarController: UITabBarController, shouldSelectTab tab: UITab) -> Bool {
            shouldSelectCalls += 1
            return answer
        }

        func tabBarController(_ tabBarController: UITabBarController, didSelectTab selectedTab: UITab, previousTab: UITab?) {
            didSelectCalls += 1
        }

        func tabBarControllerSupportedInterfaceOrientations(_ tabBarController: UITabBarController) -> UIInterfaceOrientationMask {
            .portrait
        }
    }

    private let duo = DuoLayoutHostedTests()

    private func tabBarController(in window: UIWindow) -> UITabBarController? {
        duo.controllers(in: window).lazy.compactMap { $0 as? UITabBarController }.first
    }

    // MARK: The tab bar controller's delegate

    private struct PlainTabBar {
        let controller: UITabBarController
        let host: TabBarReselectionObserver.HostController
        let tabs: [UITab]
    }

    /// A plain tab bar controller with a delegate of its own, as SwiftUI's is, and the observer's host inside its first tab.
    private func plainTabBar(delegate: OriginalDelegate) -> PlainTabBar {
        let host = TabBarReselectionObserver.HostController()
        let tabs = (0..<3).map { index in
            UITab(title: "T\(index)", image: nil, identifier: "t\(index)") { _ in
                let controller = UIViewController()
                if index == 0 { controller.addChild(host) }
                return controller
            }
        }
        let controller = UITabBarController(tabs: tabs)
        controller.delegate = delegate
        _ = controller.view
        _ = tabs[0].viewController
        return PlainTabBar(controller: controller, host: host, tabs: tabs)
    }

    @Test func theObserverKeepsSwiftUIsDelegateAndForwardsToIt() {
        let original = OriginalDelegate()
        let bar = plainTabBar(delegate: original)
        var reselected: [Int] = []
        let coordinator = TabBarReselectionObserver.Coordinator(onReselect: { reselected.append($0) })
        coordinator.attach(from: bar.host)
        #expect(bar.controller.delegate === coordinator)

        // Another tab: the original delegate decides (here: refuses), and nothing is a re-selection.
        original.answer = false
        #expect(coordinator.tabBarController(bar.controller, shouldSelectTab: bar.tabs[1]) == false)
        #expect(original.shouldSelectCalls == 1)
        #expect(reselected.isEmpty)
        // The selected tab: still asked of the original delegate, and reported.
        original.answer = true
        #expect(coordinator.tabBarController(bar.controller, shouldSelectTab: bar.tabs[0]) == true)
        #expect(original.shouldSelectCalls == 2)
        #expect(reselected == [0])
        // What the observer does not handle goes to the original delegate too.
        let orientations = #selector(UITabBarControllerDelegate.tabBarControllerSupportedInterfaceOrientations(_:))
        #expect(coordinator.responds(to: orientations))
        #expect(coordinator.forwardingTarget(for: orientations) as AnyObject? === original)
    }

    @Test func theObserverTakesTheDelegateBackWhenSwiftUIResetsIt() {
        let first = OriginalDelegate()
        let bar = plainTabBar(delegate: first)
        let coordinator = TabBarReselectionObserver.Coordinator(onReselect: { _ in })
        coordinator.attach(from: bar.host)
        let second = OriginalDelegate()
        bar.controller.delegate = second
        coordinator.attach(from: bar.host)
        #expect(bar.controller.delegate === coordinator)
        _ = coordinator.tabBarController(bar.controller, shouldSelectTab: bar.tabs[1])
        #expect(second.shouldSelectCalls == 1)
        #expect(first.shouldSelectCalls == 0)
    }

    @Test func twoObserversOnOneControllerNeverChainOrRecurse() {
        let original = OriginalDelegate()
        let bar = plainTabBar(delegate: original)
        var firstReselects: [Int] = []
        var secondReselects: [Int] = []
        let first = TabBarReselectionObserver.Coordinator(onReselect: { firstReselects.append($0) })
        let second = TabBarReselectionObserver.Coordinator(onReselect: { secondReselects.append($0) })
        // Two observers (a rebuilt view) taking the controller in turn: each adopts the original delegate, never the other observer.
        first.attach(from: bar.host)
        second.attach(from: bar.host)
        first.attach(from: bar.host)
        #expect(bar.controller.delegate === first)
        #expect(first.tabBarController(bar.controller, shouldSelectTab: bar.tabs[0]) == true)
        #expect(original.shouldSelectCalls == 1)
        #expect(firstReselects == [0])
        #expect(secondReselects.isEmpty)
    }

    @Test func theRootTabBarReselectsOnlyTheSelectedTabAndFollowsTheSelection() async throws {
        let log = HapticLog()
        let hosted = try duo.host(initial: .tab(.favorites), haptics: log.haptics)
        defer { hosted.window.isHidden = true }
        let window = hosted.window
        duo.fold(window, host: hosted.host)
        #expect(await duo.settle(window) { tabBarController(in: window)?.delegate is TabBarReselectionObserver.Coordinator })
        let controller = try #require(tabBarController(in: window))
        let delegate = try #require(controller.delegate)
        #expect(controller.selectedIndex == 1)
        // SwiftUI's own delegate was there before the observer: it is kept. Which delegate calls each side answers, for the log.
        let observer = try #require(delegate as? TabBarReselectionObserver.Coordinator)
        #expect(observer.previousDelegate != nil)
        let selectors: [(String, Selector)] = [
            ("shouldSelectTab", #selector(UITabBarControllerDelegate.tabBarController(_:shouldSelectTab:))),
            ("didSelectTab", #selector(UITabBarControllerDelegate.tabBarController(_:didSelectTab:previousTab:))),
            ("supportedOrientations", #selector(UITabBarControllerDelegate.tabBarControllerSupportedInterfaceOrientations(_:))),
            ("preferredOrientation", #selector(UITabBarControllerDelegate.tabBarControllerPreferredInterfaceOrientationForPresentation(_:)))
        ]
        let previous = observer.previousDelegate.map { String(describing: type(of: $0)) } ?? "nil"
        for (name, selector) in selectors {
            print("[426] \(name): observer=\(observer.responds(to: selector)) swiftUI(\(previous))="
                + "\(observer.previousDelegate?.responds(to: selector) ?? false)")
        }
        let selected = controller.tabs[1]
        let other = controller.tabs[2]

        #expect(delegate.tabBarController?(controller, shouldSelectTab: other) == true)
        #expect(log.played.isEmpty)
        #expect(delegate.tabBarController?(controller, shouldSelectTab: selected) == true)
        #expect(await duo.settle(window) { log.played == [.impact(.light)] })

        // UIKit tells what it selected: the model follows (legacy `handleUIKitTabSelection`, `MainWindow.swift:1613-1625`).
        delegate.tabBarController?(controller, didSelectTab: other, previousTab: selected)
        #expect(hosted.root.selectedTab == .messages)
    }
}
