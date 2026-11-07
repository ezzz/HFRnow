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

/// One choice of the icon picker.
// Port of HFRswift/Swift/AppSettingsView.swift (AppIconOption, lines 40-80) @ 2440d79. Differences: only the options whose art
// is a `.icon` in the target are offered (the loose-PNG sets of legacy are pending, see LOT-123 spec); `redface3dbig` is new.
enum AppIconOption: String, CaseIterable, Identifiable, Sendable {
    /// The primary icon (legacy "Défaut", key `superblue`).
    case superblue
    /// `Icon-RedFace3DBig.icon`, copied from legacy `AlternativeIcons/` by #581 (no legacy picker value: new key).
    case redface3dbig

    var id: String { rawValue }

    /// Picker label.
    var title: String {
        switch self {
        case .superblue: "Défaut"
        case .redface3dbig: "REDFACE 3D Big"
        }
    }

    /// The name given to `setAlternateIconName`; nil is the primary icon. Matches `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`.
    var alternateIconName: String? {
        switch self {
        case .superblue: nil
        case .redface3dbig: "Icon-RedFace3DBig"
        }
    }
}

/// The icon picker's state (LOT-123): reads the legacy `icon` key, applies a choice through the system, and stores it only once
/// the system accepted it.
@MainActor
@Observable
final class AppIconSettingsModel {
    /// The option the picker shows. A stored legacy value without art here (`classic`, `blue`, …) shows the default and is left
    /// in the store untouched, so the update from legacy loses nothing and a later release can honour it.
    private(set) var selection: AppIconOption
    /// The French message of the last failed switch, nil otherwise.
    var errorMessage: String?
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
        guard option != selection, isAvailable else { return }
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
