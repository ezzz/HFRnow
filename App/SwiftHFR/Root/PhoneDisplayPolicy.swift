import Foundation
import SwiftUI

// Port of HFRswift/Swift/PhoneDisplayPolicy.swift (PhoneDisplayKind, WindowShape, PhoneDisplayPolicy, `:1-70, 85-89`) and
// HFRswift/Swift/Common.swift (`hfrPhoneDisplayKind`, `:351-360`) @ 87fe0d1c. Differences: `usesInlineRootTitle` (`:72-83`) is not
// ported, SwiftHFR does not hang (#681, #1083); the kind is measured by `RootLayout`, which outlives a fold (GAP-713, LOT-147).
/// Which iPhone display the scene is on, as far as the iPhone Duo cover-screen rules care.
enum PhoneDisplayKind: Equatable, Sendable {
    /// An iPad, or a regular iPhone: no Duo rule applies.
    case other
    /// The iPhone Duo unfolded (inner display): `.phone` idiom, regular in both dimensions, the split root.
    case duoInner
    /// The iPhone Duo folded (cover display): `.phone` idiom, compact width, the tab bar root.
    case duoCover
}

/// The window's orientation and side inset, read in one geometry pass so they never disagree mid-rotation.
struct WindowShape: Equatable, Sendable {
    /// The window is taller than wide.
    var isPortrait = false
    /// The larger of the window's leading and trailing safe-area insets.
    var horizontalSafeAreaInset: CGFloat = 0
}

/// The pure rules behind the iPhone Duo cover-screen behaviour, kept out of the views so they can be tested.
enum PhoneDisplayPolicy {
    /// The model identifiers of the iPhone Duo (the simulator reports `iPhone19,4`, Mac check of `87fe0d1c` on #372).
    static let foldableModelIdentifiers: Set<String> = ["iPhone19,4"]

    /// Whether `identifier` (`hw.machine`, or the simulator's model) is a known foldable iPhone.
    static func isFoldableModel(_ identifier: String) -> Bool {
        foldableModelIdentifiers.contains(identifier)
    }

    /// The device's model identifier: `SIMULATOR_MODEL_IDENTIFIER` in the simulator, `hw.machine` on a device.
    static var currentModelIdentifier: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return simulated }
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { bytes in
            String(bytes: bytes.prefix { $0 != 0 }, encoding: .utf8) ?? ""
        }
    }

    /// Classifies the scene. Without the split root, a `.phone` is the Duo cover display when any of these holds, so the rule
    /// does not depend on a single signal: its model identifier is a known Duo; its system chrome lives in a vertical strip on
    /// the right edge in portrait (a side safe-area inset no other iPhone has in portrait; Mac check on #372, iOS 27.2); it was
    /// seen unfolded since launch (`hasShownExpandedLayoutThisLaunch`, kept in memory only, so a backup restored on another
    /// iPhone carries nothing).
    static func displayKind(
        isPhone: Bool, usesSidebarRoot: Bool, isFoldableModel: Bool, window: WindowShape, hasShownExpandedLayoutThisLaunch: Bool
    ) -> PhoneDisplayKind {
        guard isPhone else { return .other }
        if usesSidebarRoot { return .duoInner }
        let hasSideChromeInPortrait = window.isPortrait && window.horizontalSafeAreaInset > 0
        return isFoldableModel || hasSideChromeInPortrait || hasShownExpandedLayoutThisLaunch ? .duoCover : .other
    }

    /// Whether « Actualiser » and « Retour » go to the bottom of the toolbar. On the cover screen the toolbar is a column on
    /// the right edge, and only its bottom is within thumb reach (beta feedback on #372).
    static func placesThumbActionsAtBottom(kind: PhoneDisplayKind) -> Bool {
        kind == .duoCover
    }
}

extension EnvironmentValues {
    /// Set by `RootLayout`: which iPhone Duo display the scene is on (`.other` elsewhere, and outside the roots).
    @Entry var phoneDisplayKind: PhoneDisplayKind = .other
    /// The model identifier `RootLayout` classifies; nil is the device's. Tests set it: the Duo simulator reports `iPhone19,4` to
    /// every process, a regular one never does, so the other signals could not be checked alone.
    @Entry var rootLayoutModelIdentifier: String?
}
