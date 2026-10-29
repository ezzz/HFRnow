import HFRModels
import HFRStorage
import UIKit

/// Which orientations the app supports, from the rotation setting (`landscape_mode`).
///
/// Ported from `HFRSwiftOrientationPolicy.supportedInterfaceOrientations` (legacy `Common.swift:187-195`): an iPad always
/// rotates; an iPhone rotates (never upside down) unless rotation is locked. The composer's own portrait lock
/// (`lockForAnswerViewIfNeeded`) belongs to the composer lot (LOT-084).
enum OrientationPolicy {
    /// The mask for a device of `idiom` with rotation allowed or not.
    static func supported(idiom: UIUserInterfaceIdiom, rotationAllowed: Bool) -> UIInterfaceOrientationMask {
        guard idiom == .phone else { return .all }
        return rotationAllowed ? .allButUpsideDown : .portrait
    }

    /// The mask right now, reading the setting each time so a change applies without a restart.
    @MainActor
    static func supported(
        idiom: UIUserInterfaceIdiom = UIDevice.current.userInterfaceIdiom,
        store: any SettingsStore = UserDefaultsSettingsStore()
    ) -> UIInterfaceOrientationMask {
        supported(idiom: idiom, rotationAllowed: store.value(for: SettingKey.landscapeMode) != .none)
    }

    /// Asks the open scenes to re-read the mask, so locking turns an iPhone held in landscape back to portrait at once.
    @MainActor
    static func refresh() {
        guard UIDevice.current.userInterfaceIdiom == .phone else { return }
        let mask = supported()
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows {
                window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
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
