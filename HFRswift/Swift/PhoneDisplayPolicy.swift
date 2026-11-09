import CoreGraphics
import Foundation

/// Which iPhone display the scene is on, as far as the iPhone Duo workarounds care.
enum PhoneDisplayKind: Equatable {
    /// iPad, or a regular iPhone: no Duo workaround applies.
    case other
    /// iPhone Duo unfolded (inner display): `.phone` idiom, regular/regular, split view root.
    case duoInner
    /// iPhone Duo folded (cover display): `.phone` idiom, compact width, tab bar root.
    case duoCover
}

/// Window orientation and side inset, read in one geometry pass so they never disagree mid-rotation.
struct WindowShape: Equatable {
    /// The window is taller than wide.
    var isPortrait = false
    /// The larger of the window's leading and trailing safe area insets.
    var horizontalSafeAreaInset: CGFloat = 0
}

/// Pure rules behind the iPhone Duo workarounds, kept out of the views so they can be unit tested.
enum PhoneDisplayPolicy {
    /// Model identifiers of the iPhone Duo (the simulator reports `iPhone19,4`, Mac check on #372).
    static let foldableModelIdentifiers: Set<String> = ["iPhone19,4"]

    /// Whether `identifier` (`hw.machine`, or the simulator's model) is a known foldable iPhone.
    static func isFoldableModel(_ identifier: String) -> Bool {
        foldableModelIdentifiers.contains(identifier)
    }

    /// The device's model identifier: `SIMULATOR_MODEL_IDENTIFIER` in the simulator, `hw.machine` on a device.
    static var currentModelIdentifier: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulated
        }
        var info = utsname()
        uname(&info)
        return withUnsafeBytes(of: &info.machine) { bytes in
            String(bytes: bytes.prefix { $0 != 0 }, encoding: .utf8) ?? ""
        }
    }

    /// Classifies the scene.
    /// - Parameters:
    ///   - isPhone: `UIDevice.current.userInterfaceIdiom == .phone`.
    ///   - usesSidebarRoot: the scene shows the split view root (regular/regular).
    ///   - isFoldableModel: the model identifier is a known iPhone Duo (`isFoldableModel(_:)`).
    ///   - window: portrait flag and side safe-area inset, measured together.
    ///   - hasShownExpandedLayoutThisLaunch: this process already showed the split view root on a `.phone`
    ///     (kept in memory only, so a backup restored on another iPhone carries nothing).
    ///
    /// Without the split view root, a phone is the Duo cover display when any of these holds, so the
    /// freeze workaround does not depend on a single signal:
    /// - its model identifier is a known Duo;
    /// - its system chrome lives in a vertical strip on the right edge in portrait (side safe-area
    ///   inset that no other iPhone has in portrait; Mac check on #372, Duo simulator, iOS 27.2);
    /// - it was seen unfolded since launch.
    static func displayKind(
        isPhone: Bool,
        usesSidebarRoot: Bool,
        isFoldableModel: Bool,
        window: WindowShape,
        hasShownExpandedLayoutThisLaunch: Bool
    ) -> PhoneDisplayKind {
        guard isPhone else { return .other }
        if usesSidebarRoot { return .duoInner }
        let hasSideChromeInPortrait = window.isPortrait && window.horizontalSafeAreaInset > 0
        return isFoldableModel || hasSideChromeInPortrait || hasShownExpandedLayoutThisLaunch ? .duoCover : .other
    }

    /// Whether the tab root titles must stay inline. iOS 27.1/27.2 on the iPhone Duo hangs in
    /// `UINavigationController` layout (`_observeScrollViewDidScroll` / `_updateSafeAreaInsets`)
    /// when a view is pushed after a large title collapsed on scroll, on both displays.
    /// - Parameters:
    ///   - kind: the scene's display, as published by `RootTabView`.
    ///   - isPhone: `UIDevice.current.userInterfaceIdiom == .phone`.
    ///   - isRegularInBothDimensions: the size classes read where the modifier is applied (fallback
    ///     for a view outside `RootTabView`, which then has no `kind`).
    static func usesInlineRootTitle(kind: PhoneDisplayKind, isPhone: Bool, isRegularInBothDimensions: Bool) -> Bool {
        guard isPhone else { return false }
        return kind != .other || isRegularInBothDimensions
    }

    /// Whether « Actualiser » and « Retour » go to the bottom of the toolbar. On the cover screen
    /// the toolbar is a column on the right edge, and only its bottom is within thumb reach.
    static func placesThumbActionsAtBottom(kind: PhoneDisplayKind) -> Bool {
        kind == .duoCover
    }
}
