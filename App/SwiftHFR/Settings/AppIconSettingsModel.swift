import HFRStorage
import Observation
import UIKit

/// The system's alternate-icon API, behind a seam so the model is testable without a device.
@MainActor
protocol AlternateIconSwitching {
    /// False where the system refuses alternate icons (`UIApplication.supportsAlternateIcons`).
    var supportsAlternateIcons: Bool { get }
    /// The icon the system shows now: an alternate's name, nil for the primary icon.
    var alternateIconName: String? { get }
    /// Applies the alternate icon `name`, or the primary icon for nil.
    func setAlternateIconName(_ name: String?) async throws
}

/// `UIApplication` as the live switcher.
@MainActor
struct SystemAlternateIconSwitcher: AlternateIconSwitching {
    var supportsAlternateIcons: Bool { UIApplication.shared.supportsAlternateIcons }

    var alternateIconName: String? { UIApplication.shared.alternateIconName }

    func setAlternateIconName(_ name: String?) async throws {
        try await UIApplication.shared.setAlternateIconName(name)
    }
}

/// The icon picker's state (LOT-123): reads the legacy `icon` key, applies a choice through the system, and stores it only once
/// the system accepted it.
@MainActor
@Observable
final class AppIconSettingsModel {
    /// The option the picker shows: the icon the system currently shows (legacy wrote the key before applying, so a refused switch
    /// leaves the store wrong), else the stored value, else the default. The store is left untouched until a choice succeeds.
    private(set) var selection: AppIconOption
    /// The French message of the last failed switch, nil otherwise.
    var errorMessage: String?
    /// True while the system applies an icon; further choices are ignored (a second call could be refused and show a false error).
    private(set) var isSwitching = false
    /// False where the system has no alternate icons: the picker is disabled.
    var isAvailable: Bool { switcher.supportsAlternateIcons }

    @ObservationIgnored private let store: any SettingsStore
    @ObservationIgnored private let switcher: any AlternateIconSwitching
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let now: () -> Date

    /// Reads the system's current icon, falling back to the choice in `store`. `calendar` and `now` decide which dated icons are offered.
    init(
        store: any SettingsStore,
        switcher: any AlternateIconSwitching = SystemAlternateIconSwitcher(),
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init
    ) {
        self.store = store
        self.switcher = switcher
        self.calendar = calendar
        self.now = now
        selection = AppIconOption.current(store: store, switcher: switcher)
    }

    /// The options to show, by pack in picker order: those offered today, plus the active one even after its window ended (the
    /// icon stays until the user switches it, so the ring shows where they are). Packs with nothing to show are left out.
    var sections: [AppIconSection] {
        let date = now()
        return AppIconPack.allCases.compactMap { pack in
            let options = AppIconOption.allCases.filter {
                $0.pack == pack && ($0 == selection || $0.isOffered(on: date, calendar: calendar))
            }
            return options.isEmpty ? nil : AppIconSection(pack: pack, options: options)
        }
    }

    /// Applies `option`; on a refusal the selection and the store keep their previous value and `errorMessage` is set.
    func select(_ option: AppIconOption) async {
        guard option != selection, isAvailable, !isSwitching, option.isOffered(on: now(), calendar: calendar) else { return }
        isSwitching = true
        defer { isSwitching = false }
        errorMessage = nil
        do {
            try await switcher.setAlternateIconName(option.alternateIconName)
            rememberPrevious(replacedBy: option)
            selection = option
            store.set(option.rawValue, for: SettingKey.appIconName)
        } catch {
            errorMessage = "Impossible de changer l’icône : \(error.localizedDescription)"
        }
    }

    /// Keeps the icon a dated one replaces, for the question after its window; a dated icon replacing a dated one keeps the older
    /// choice, and any plain icon clears it.
    private func rememberPrevious(replacedBy option: AppIconOption) {
        if option.window == nil {
            store.set(nil, for: SettingKey.appIconPrevious)
        } else if selection.window == nil {
            store.set(selection.rawValue, for: SettingKey.appIconPrevious)
        }
    }
}

/// The options of one pack, as the picker lists them.
struct AppIconSection: Identifiable, Equatable, Sendable {
    let pack: AppIconPack
    let options: [AppIconOption]

    var id: String { pack.rawValue }
}

extension AppIconOption {
    /// The option the system shows now (an alternate's name, nil for the primary icon), else the stored one, else the default.
    @MainActor
    static func current(store: any SettingsStore, switcher: any AlternateIconSwitching) -> AppIconOption {
        let stored = AppIconOption(rawValue: store.value(for: SettingKey.appIconName)) ?? .superblue
        guard switcher.supportsAlternateIcons else { return stored }
        let name = switcher.alternateIconName
        return allCases.first { $0.alternateIconName == name } ?? stored
    }
}
