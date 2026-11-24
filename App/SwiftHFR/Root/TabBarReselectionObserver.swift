import SwiftUI
import UIKit

// Port of HFRswift/Swift/MainWindow.swift (TabBarReselectionObserver, `:2597-2790`; `handleUIKitTabReselection`, `:2453-2494`) @ 87fe0d1c
// (GAP-007, UXD-04, #426). Differences: iOS 27 only (the `shouldSelectTab` delegate), no notification: the tapped index goes to a closure.
/// Tells when the tab the tab bar already shows is tapped again: SwiftUI's `TabView` does not call its selection binding for it, so
/// this finds the `UITabBarController` behind the tab bar and listens as its delegate. Put it in the `TabView`'s background.
struct TabBarReselectionObserver: UIViewControllerRepresentable {
    /// Called with the index of the tab that was tapped again, counted from the left of the bar.
    let onReselect: @MainActor (Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onReselect: onReselect) }

    func makeUIViewController(context: Context) -> HostController {
        let host = HostController()
        host.onHierarchyUpdate = { [coordinator = context.coordinator] in coordinator.attach(from: $0) }
        return host
    }

    func updateUIViewController(_ host: HostController, context: Context) {
        context.coordinator.onReselect = onReselect
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

    /// The tab bar controller's delegate: a tap on the selected tab is a re-selection; the selection itself is left to SwiftUI.
    @MainActor
    final class Coordinator: NSObject, UITabBarControllerDelegate {
        var onReselect: @MainActor (Int) -> Void
        private weak var tabBarController: UITabBarController?

        init(onReselect: @escaping @MainActor (Int) -> Void) {
            self.onReselect = onReselect
        }

        func attach(from host: UIViewController) {
            let found = host.tabBarController ?? Self.tabBarController(in: host.view.window?.rootViewController)
            guard let found, found !== tabBarController else { return }
            tabBarController = found
            found.delegate = self
        }

        func tabBarController(_ tabBarController: UITabBarController, shouldSelectTab tab: UITab) -> Bool {
            if let tapped = tabBarController.tabs.firstIndex(where: { $0 === tab || $0.identifier == tab.identifier }),
               tapped == tabBarController.selectedIndex {
                onReselect(tapped)
            }
            return true
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
