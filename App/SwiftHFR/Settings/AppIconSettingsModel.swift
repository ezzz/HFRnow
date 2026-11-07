import HFRStorage
import Observation
import UIKit

/// The system's alternate-icon API, behind a seam so the model is testable without a device.
@MainActor
protocol AlternateIconSwitching {
    /// False where the system refuses alternate icons (`UIApplication.supportsAlternateIcons`).
    var supportsAlternateIcons: Bool { get }
    /// Applies the alternate icon `name`, or the primary icon for nil.
    func setAlternateIconName(_ name: String?) async throws
}

/// `UIApplication` as the live switcher.
@MainActor
struct SystemAlternateIconSwitcher: AlternateIconSwitching {
    var supportsAlternateIcons: Bool { UIApplication.shared.supportsAlternateIcons }

    func setAlternateIconName(_ name: String?) async throws {
        try await UIApplication.shared.setAlternateIconName(name)
    }
}

// Port of HFRswift/Swift/AppSettingsView.swift (AppIconOption, lines 40-80) @ 2440d79. Differences: the art is the layered `.icon` of
// each legacy set (redone or reused by the Mac art PR, same names); `redface3dbig` is new (`Icon-RedFace3DBig`, no legacy value).
// The `.icon` names live here only: a redrawn icon swaps in under the same name with no code change.
/// One choice of the icon picker.
enum AppIconOption: String, CaseIterable, Identifiable, Sendable {
    /// The primary icon (legacy "Défaut", key `superblue`).
    case superblue
    case classic
    case classicRed = "classic-red"
    case redface
    case redfaceBlue = "redface-blue"
    case beta
    case blue
    case white
    case redface3dbig

    var id: String { rawValue }

    /// Picker label (legacy titles).
    var title: String {
        switch self {
        case .superblue: "Défaut"
        case .classic: "Classique Yellow"
        case .classicRed: "Classique Red"
        case .redface: "REDFACE"
        case .redfaceBlue: "REDFACE Blue"
        case .beta: "Beta"
        case .blue: "Blue"
        case .white: "White"
        case .redface3dbig: "REDFACE 3D Big"
        }
    }

    /// The name given to `setAlternateIconName`; nil is the primary icon. Each matches an `.icon` in `App/SwiftHFR/` and
    /// `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`; the legacy ones are the legacy names (`alternateIconName`, :61-83).
    var alternateIconName: String? {
        switch self {
        case .superblue: nil
        case .classic: "Icon-CLASSIC"
        case .classicRed: "Icon-CLASSIC-RED"
        case .redface: "Icon-REDFACE"
        case .redfaceBlue: "Icon-REDFACEBLUE"
        case .beta: "Icon-BETA"
        case .blue: "Icon-BLUE"
        case .white: "Icon-WHITE"
        case .redface3dbig: "Icon-RedFace3DBig"
        }
    }
}

/// The icon picker's state (LOT-123): reads the legacy `icon` key, applies a choice through the system, and stores it only once
/// the system accepted it.
@MainActor
@Observable
final class AppIconSettingsModel {
    /// The option the picker shows. A stored value that is no option (corrupt, or from a newer build) shows the default and is left
    /// in the store untouched.
    private(set) var selection: AppIconOption
    /// The French message of the last failed switch, nil otherwise.
    var errorMessage: String?
    /// True while the system applies an icon; further choices are ignored (a second call could be refused and show a false error).
    private(set) var isSwitching = false
    /// False where the system has no alternate icons: the picker is disabled.
    var isAvailable: Bool { switcher.supportsAlternateIcons }

    @ObservationIgnored private let store: any SettingsStore
    @ObservationIgnored private let switcher: any AlternateIconSwitching

    /// Reads the stored choice from `store`.
    init(store: any SettingsStore, switcher: any AlternateIconSwitching = SystemAlternateIconSwitcher()) {
        self.store = store
        self.switcher = switcher
        selection = AppIconOption(rawValue: store.value(for: SettingKey.appIconName)) ?? .superblue
    }

    /// Applies `option`; on a refusal the selection and the store keep their previous value and `errorMessage` is set.
    func select(_ option: AppIconOption) async {
        guard option != selection, isAvailable, !isSwitching else { return }
        isSwitching = true
        defer { isSwitching = false }
        errorMessage = nil
        do {
            try await switcher.setAlternateIconName(option.alternateIconName)
            selection = option
            store.set(option.rawValue, for: SettingKey.appIconName)
        } catch {
            errorMessage = "Impossible de changer l’icône : \(error.localizedDescription)"
        }
    }
}
