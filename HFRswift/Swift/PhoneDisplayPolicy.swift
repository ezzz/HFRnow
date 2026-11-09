import CoreGraphics

/// Which iPhone display the scene is on, as far as the iPhone Duo workarounds care.
enum PhoneDisplayKind: Equatable {
    /// iPad, or a regular iPhone: no Duo workaround applies.
    case other
    /// iPhone Duo unfolded (inner display): `.phone` idiom, regular/regular, split view root.
    case duoInner
    /// iPhone Duo folded (cover display): `.phone` idiom, compact width, tab bar root.
    case duoCover
}

/// Pure rules behind the iPhone Duo workarounds, kept out of the views so they can be unit tested.
enum PhoneDisplayPolicy {
    /// UserDefaults key remembering that this device once showed a `.phone` regular/regular scene,
    /// which only a foldable iPhone does (the Pro Max in landscape is regular/compact).
    static let hasShownExpandedLayoutKey = "HFRswiftPhoneHasShownExpandedLayout"

    /// Classifies the scene.
    /// - Parameters:
    ///   - isPhone: `UIDevice.current.userInterfaceIdiom == .phone`.
    ///   - usesSidebarRoot: the scene shows the split view root (regular/regular).
    ///   - isPortrait: the window is taller than wide.
    ///   - horizontalSafeAreaInset: the larger of the window's leading and trailing safe area insets.
    ///   - hasShownExpandedLayout: this device has already shown the split view root on a `.phone`.
    ///
    /// The cover display is recognised two ways, because the device can start folded:
    /// - its system chrome (status bar, toolbar, tab bar) lives in a vertical strip on the right edge
    ///   in portrait, so the window has a side safe-area inset that no other iPhone has in portrait
    ///   (Mac check of #372 on the Duo simulator, iOS 27.2);
    /// - or the device has already been seen unfolded.
    static func displayKind(
        isPhone: Bool,
        usesSidebarRoot: Bool,
        isPortrait: Bool,
        horizontalSafeAreaInset: CGFloat,
        hasShownExpandedLayout: Bool
    ) -> PhoneDisplayKind {
        guard isPhone else { return .other }
        if usesSidebarRoot { return .duoInner }
        let hasSideChromeInPortrait = isPortrait && horizontalSafeAreaInset > 0
        return hasSideChromeInPortrait || hasShownExpandedLayout ? .duoCover : .other
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
}
