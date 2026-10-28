import HFRModels
import HFRStorage
import Observation

/// The "Général" settings: each property reads its legacy key at creation and writes it back on every change, so what the
/// screen shows is what the store holds (LOT-119).
///
/// Settings of other lots are not here: favourites options (LOT-124), haptics and icon (LOT-123), theme (LOT-121),
/// blocklists (LOT-118), maintenance and about (LOT-120). The tab-bar option (`tabbar_minimize_on_scroll`) is dropped on
/// purpose: the split view has no tab bar.
@MainActor
@Observable
final class GeneralSettingsModel {
    /// Where the app opens.
    var startupScreen: StartupScreen {
        didSet { if startupScreen != oldValue { store.set(startupScreen, for: SettingKey.startupScreen) } }
    }
    /// False locks an iPhone to portrait (`landscape_mode == none`); an iPad always rotates.
    var allowsRotation: Bool {
        didSet {
            guard allowsRotation != oldValue else { return }
            store.set(allowsRotation ? .galerieMessage : LandscapeMode.none, for: SettingKey.landscapeMode)
            rotationChanged()
        }
    }
    /// True opens external links in the system browser instead of the in-app one.
    var opensLinksInDefaultBrowser: Bool {
        didSet {
            if opensLinksInDefaultBrowser != oldValue { store.set(opensLinksInDefaultBrowser, for: SettingKey.opensLinksInDefaultBrowser) }
        }
    }
    /// Message text size.
    var textSizeScale: TextSizeScale {
        didSet { if textSizeScale != oldValue { store.set(textSizeScale, for: SettingKey.textSizeScale) } }
    }
    /// Denser lists.
    var compactMode: Bool {
        didSet { if compactMode != oldValue { store.set(compactMode, for: SettingKey.compactMode) } }
    }

    @ObservationIgnored private let store: any SettingsStore
    @ObservationIgnored private let rotationChanged: @MainActor () -> Void

    /// Reads the current values from `store`. `rotationChanged` runs after the rotation switch, to re-apply the orientation.
    init(store: any SettingsStore, rotationChanged: @escaping @MainActor () -> Void = {}) {
        self.store = store
        self.rotationChanged = rotationChanged
        startupScreen = store.value(for: SettingKey.startupScreen)
        allowsRotation = store.value(for: SettingKey.landscapeMode) != .none
        opensLinksInDefaultBrowser = store.value(for: SettingKey.opensLinksInDefaultBrowser)
        textSizeScale = store.value(for: SettingKey.textSizeScale)
        compactMode = store.value(for: SettingKey.compactMode)
    }
}

extension TextSizeScale {
    /// Picker label (legacy `AppTextSizeScale.title`, `Common.swift:275-286`).
    var title: String {
        switch self {
        case .percent100: "Standard"
        case .percent110: "+10 %"
        case .percent120: "+20 %"
        case .percent130: "+30 %"
        }
    }
}
