import SwiftUI
import UIKit

// Port of HFRswift/Swift/MainWindow.swift (TabBarReselectionObserver, `:2597-2790`; `tabBarReselectionObserver`, `:2444-2451`;
// `handleUIKitTabReselection`, `:2453-2494`; `handleUIKitTabSelection`, `:1613-1625`) @ 87fe0d1c (GAP-007, UXD-04, #426).
// Differences: iOS 27 only (the `shouldSelectTab` delegate); no notification, the tapped index goes to a closure; SwiftUI's own
// delegate is kept and forwarded to.
/// Tells when the tab the tab bar already shows is tapped again: SwiftUI's `TabView` does not call its selection binding for it, so
/// this finds the `UITabBarController` behind the tab bar and listens as its delegate, keeping the delegate SwiftUI installed and
/// forwarding to it, so SwiftUI's own selection handling still runs. Put it in the `TabView`'s background.
struct TabBarReselectionObserver: UIViewControllerRepresentable {
    /// Called with the index of the tab that was tapped again, counted from the left of the bar.
    let onReselect: @MainActor (Int) -> Void
    /// Called with the index of the tab UIKit selected, after SwiftUI's delegate has seen it (legacy `onSelect`: the model follows).
    var onSelect: @MainActor (Int) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(onReselect: onReselect, onSelect: onSelect) }

    func makeUIViewController(context: Context) -> HostController {
        let host = HostController()
        host.onHierarchyUpdate = { [coordinator = context.coordinator] in coordinator.attach(from: $0) }
        return host
    }

    func updateUIViewController(_ host: HostController, context: Context) {
        context.coordinator.onReselect = onReselect
        context.coordinator.onSelect = onSelect
        context.coordinator.attach(from: host)
    }

    /// A controller that reports each time it joins a hierarchy, when the tab bar controller can be found.
    final class HostController: UIViewController {
        var onHierarchyUpdate: ((UIViewController) -> Void)?

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            onHierarchyUpdate?(self)
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            onHierarchyUpdate?(self)
        }
    }

    /// The tab bar controller's delegate: a tap on the selected tab is a re-selection. The delegate that was there (SwiftUI's) is kept
    /// and asked first, for `shouldSelectTab` and `didSelectTab`, and every other delegate call goes to it (`forwardingTarget`).
    @MainActor
    final class Coordinator: NSObject, UITabBarControllerDelegate {
        var onReselect: @MainActor (Int) -> Void
        var onSelect: @MainActor (Int) -> Void
        private weak var tabBarController: UITabBarController?
        /// The delegate that was on the controller before: weak, as the controller's own reference is, and never another
        /// observer (a rebuilt view attaches a new one), or two of them would forward to each other without end.
        private(set) weak var previousDelegate: (any UITabBarControllerDelegate)?

        init(onReselect: @escaping @MainActor (Int) -> Void, onSelect: @escaping @MainActor (Int) -> Void = { _ in }) {
            self.onReselect = onReselect
            self.onSelect = onSelect
        }

        /// Installs itself as the delegate, again when SwiftUI put another one back on the same controller.
        func attach(from host: UIViewController) {
            let found = host.tabBarController ?? Self.tabBarController(in: host.view.window?.rootViewController)
            guard let found, found.delegate !== self else { return }
            let current = found.delegate
            previousDelegate = (current as? Coordinator).map(\.previousDelegate) ?? current
            tabBarController = found
            found.delegate = self
        }

        override func responds(to selector: Selector?) -> Bool {
            super.responds(to: selector) || previousDelegate?.responds(to: selector) == true
        }

        override func forwardingTarget(for selector: Selector?) -> Any? {
            previousDelegate?.responds(to: selector) == true ? previousDelegate : super.forwardingTarget(for: selector)
        }

        func tabBarController(_ tabBarController: UITabBarController, shouldSelectTab tab: UITab) -> Bool {
            let allowed = previousDelegate?.tabBarController?(tabBarController, shouldSelectTab: tab) ?? true
            if allowed, let tapped = Self.index(of: tab, in: tabBarController), tapped == tabBarController.selectedIndex {
                onReselect(tapped)
            }
            return allowed
        }

        func tabBarController(_ tabBarController: UITabBarController, didSelectTab selectedTab: UITab, previousTab: UITab?) {
            previousDelegate?.tabBarController?(tabBarController, didSelectTab: selectedTab, previousTab: previousTab)
            if let index = Self.index(of: selectedTab, in: tabBarController) { onSelect(index) }
        }

        private static func index(of tab: UITab, in tabBarController: UITabBarController) -> Int? {
            tabBarController.tabs.firstIndex { $0 === tab || $0.identifier == tab.identifier }
        }

        private static func tabBarController(in root: UIViewController?) -> UITabBarController? {
            guard let root else { return nil }
            if let found = root as? UITabBarController { return found }
            for child in root.children {
                if let found = tabBarController(in: child) { return found }
            }
            return root.presentedViewController.flatMap { tabBarController(in: $0) }
        }
    }
}
