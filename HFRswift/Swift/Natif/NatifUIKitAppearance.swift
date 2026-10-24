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
        appearance.selectedSegmentTintColor = fill
        appearance.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
    }
}
