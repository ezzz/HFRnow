import HFRModels
import HFRStorage
import UIKit

// Port of HFRswift/Swift/Common.swift (AppScreenRotation, HFRSwiftOrientationPolicy) @ 87fe0d1c (`:187-242`, the same at
// 2fe43da3; the iPhone Duo rule is `796b34bd`). Differences: the rule (idiom + setting + unfolded → orientation mask) is a pure
// function apart from the device read; the portrait lock while composing is not ported yet.
/// Which orientations the app supports, from the rotation setting (`landscape_mode`).
///
/// Ported from `HFRSwiftOrientationPolicy.supportedInterfaceOrientations` (legacy `Common.swift:187-200` @ 87fe0d1c): an iPad
/// always rotates; an iPhone Duo unfolded (a scene regular in both dimensions) rotates whatever the setting, as the system
/// ignores the supported orientations there (GAP-213); any other iPhone rotates (never upside down) unless rotation is locked.
/// The composer's own portrait lock (`lockForAnswerViewIfNeeded`) belongs to the composer lot (LOT-084).
enum OrientationPolicy {
    /// The mask for a device of `idiom` with rotation allowed or not, on a scene regular in both dimensions (`expanded`) or not.
    static func supported(
        idiom: UIUserInterfaceIdiom, rotationAllowed: Bool, expanded: Bool = false
    ) -> UIInterfaceOrientationMask {
        guard idiom == .phone else { return .all }
        // Unfolded iPhone Duo: every orientation but upside down (not in the iPhone Info.plist list), like the iPad.
        if expanded { return .allButUpsideDown }
        return rotationAllowed ? .allButUpsideDown : .portrait
    }

    /// The mask right now, reading the setting each time so a change applies without a restart.
    @MainActor
    static func supported(
        idiom: UIUserInterfaceIdiom = UIDevice.current.userInterfaceIdiom,
        store: any SettingsStore = UserDefaultsSettingsStore(),
        expanded: Bool = showsExpandedPhoneLayout()
    ) -> UIInterfaceOrientationMask {
        supported(idiom: idiom, rotationAllowed: store.value(for: SettingKey.landscapeMode) != .none, expanded: expanded)
    }

    /// Whether `traits` are regular in both dimensions: on a `.phone`, the iPhone Duo's inner screen.
    static func isExpanded(_ traits: UITraitCollection) -> Bool {
        traits.horizontalSizeClass == .regular && traits.verticalSizeClass == .regular
    }

    /// Whether a scene of the app shows the unfolded layout (legacy `isShowingExpandedPhoneLayout`, `Common.swift:216-220`).
    @MainActor
    static func showsExpandedPhoneLayout() -> Bool {
        UIApplication.shared.connectedScenes.contains { ($0 as? UIWindowScene).map { isExpanded($0.traitCollection) } ?? false }
    }

    /// Asks the open scenes to re-read the mask, so locking turns an iPhone held in landscape back to portrait at once. A scene
    /// regular in both dimensions (the unfolded Duo) is not asked to rotate: the system ignores it there (legacy
    /// `refreshSupportedOrientations`, `Common.swift:222-242` @ 87fe0d1c).
    @MainActor
    static func refresh() {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        let mask = supported()
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows {
                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
            guard !isExpanded(scene.traitCollection) else { continue }
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
        }
    }
}

/// Hands the orientation mask to UIKit: SwiftUI has no setting for it.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        OrientationPolicy.supported()
    }
}
