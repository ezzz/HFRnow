//
//  NatifUIKitAppearance.swift
//  HFRswift
//
//  UIKit controls that the SwiftUI tint does not reach.
//

import UIKit

@objc final class NatifUIKitAppearance: NSObject {
    /// Segmented controls: selected segment filled with the accent, white title. The default dark
    /// title was hard to read on the accent, and the light text accent was too pale under white.
    @objc static func apply() {
        let accent = NatifAccent.accent(at: NatifAppearance.accentIndex())
        let fill = UIColor { traits in
            traits.userInterfaceStyle == .dark ? accent.darkFill : accent.light
        }
        let appearance = UISegmentedControl.appearance()
        let segmentFill: UIColor? = fill
        let selectedTitle: [NSAttributedString.Key: Any]? = [.foregroundColor: UIColor.white]
        appearance.selectedSegmentTintColor = segmentFill
        appearance.setTitleTextAttributes(selectedTitle, for: .selected)

        // The appearance proxy only reaches controls created afterwards: update the visible ones.
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows {
                updateSegmentedControls(in: window, fill: segmentFill, selectedTitle: selectedTitle)
            }
        }
    }

    private static func updateSegmentedControls(
        in view: UIView,
        fill: UIColor?,
        selectedTitle: [NSAttributedString.Key: Any]?
    ) {
        if let control = view as? UISegmentedControl {
            control.selectedSegmentTintColor = fill
            control.setTitleTextAttributes(selectedTitle, for: .selected)
        }
        for subview in view.subviews {
            updateSegmentedControls(in: subview, fill: fill, selectedTitle: selectedTitle)
        }
    }
}
