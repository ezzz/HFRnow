//
//  NatifBackButton.swift
//  HFRswift
//
//  Back button in the accent colour. The iOS 26 system back button is always monochrome, so
//  pushed screens replace it with their own chevron and keep the swipe back.
//

import SwiftUI
import UIKit

private struct NatifBackButton: ViewModifier {
    let isEnabled: Bool
    let alwaysHidesTabBar: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isPresented) private var isPresented
    @AppStorage(NatifAppearance.accentKey) private var accentID = 0

    private var showsButton: Bool { isEnabled && isPresented }

    func body(content: Content) -> some View {
        if showsButton {
            content
                .rootTabBarVisibility(alwaysHidden: alwaysHidesTabBar)
                .navigationBarBackButtonHidden(true)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Retour", systemImage: "chevron.backward") {
                            dismiss()
                        }
                        // Bar items keep the tint they were created with.
                        .id(accentID)
                    }
                }
                .background {
                    InteractivePopGestureEnabler()
                        .frame(width: 0, height: 0)
                        .accessibilityHidden(true)
                }
        } else {
            content
                .rootTabBarVisibility(alwaysHidden: alwaysHidesTabBar)
        }
    }
}

extension View {
    /// Pushed screen without its own bar items: tinted back button and the sidebar toggle.
    func natifPushedScreen() -> some View {
        natifBackButton()
            .rootSidebarRevealButton()
    }

    /// Replaces the system back button of a pushed screen by one in the accent colour.
    /// `isEnabled: false` keeps the system button (e.g. when the screen shows its own back button).
    /// `alwaysHidesTabBar`: topic pages, whose bottom bar (‹ › and reply) cannot share the screen
    /// with the tab bar.
    func natifBackButton(isEnabled: Bool = true, alwaysHidesTabBar: Bool = false) -> some View {
        modifier(NatifBackButton(isEnabled: isEnabled, alwaysHidesTabBar: alwaysHidesTabBar))
    }

    /// The `.automatic` used in compact width by `rootTabBarHiddenInRegularWidth` overrode the
    /// `.hidden` set by the caller on topic pages: the tab bar then pushed the bottom bar items
    /// into an overflow "•••" menu and left an empty button (folded Duo).
    @ViewBuilder
    fileprivate func rootTabBarVisibility(alwaysHidden: Bool) -> some View {
        if alwaysHidden {
            toolbar(.hidden, for: .tabBar)
        } else {
            rootTabBarHiddenInRegularWidth()
        }
    }
}

/// Hiding the system back button disables the edge swipe back; this restores it.
private struct InteractivePopGestureEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ uiViewController: Controller, context: Context) {}

    final class Controller: UIViewController {
        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            enableSwipeBack()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            enableSwipeBack()
        }

        private func enableSwipeBack() {
            guard let navigationController else { return }
            let delegate = PopGestureDelegate.delegate(for: navigationController)
            var recognizers = [navigationController.interactivePopGestureRecognizer]
            if #available(iOS 26.0, *) {
                // iOS 26 also pops with a swipe anywhere on the content.
                recognizers.append(navigationController.interactiveContentPopGestureRecognizer)
            }
            for recognizer in recognizers.compactMap({ $0 }) {
                if recognizer.delegate !== delegate {
                    recognizer.delegate = delegate
                }
                recognizer.isEnabled = true
            }
        }
    }
}

private final class PopGestureDelegate: NSObject, UIGestureRecognizerDelegate {
    private static var key: UInt8 = 0
    weak var navigationController: UINavigationController?

    static func delegate(for navigationController: UINavigationController) -> PopGestureDelegate {
        if let existing = objc_getAssociatedObject(navigationController, &key) as? PopGestureDelegate {
            return existing
        }
        let delegate = PopGestureDelegate()
        delegate.navigationController = navigationController
        objc_setAssociatedObject(navigationController, &key, delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return delegate
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        (navigationController?.viewControllers.count ?? 0) > 1
    }

    /// Lets the swipe back win over the content gestures (lists, web view, row buttons).
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        gestureRecognizer === navigationController?.interactivePopGestureRecognizer
    }
}
