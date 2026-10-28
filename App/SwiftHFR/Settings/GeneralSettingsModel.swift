import HFRModels
import HFRStorage
import Observation

/// The "Général" settings: each property reads its legacy key at creation and writes it back on every change, so what the
/// screen shows is what the store holds (LOT-119).
///
/// Settings of other lots are not here: favourites options (LOT-124), haptics and icon (LOT-123), theme (LOT-121),
/// blocklists (LOT-118), maintenance and about (LOT-120).
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
    /// In-app text size in percent, an offset on top of Dynamic Type (below 100 gives a denser display).
    /// TODO: applying it across the screens is a separate lot (opened by the tracking session); until then it is stored only.
    var textSizePercent: Int {
        didSet {
            let clamped = Self.clamp(textSizePercent)
            if clamped != textSizePercent { textSizePercent = clamped; return }
            if textSizePercent != oldValue { store.set(textSizePercent, for: SettingKey.textSizePercent) }
        }
    }
    /// Minimise the tab bar while scrolling (`tabbar_minimize_on_scroll`, default on). Read by the root tab bar (LOT-170).
    var minimizesTabBarOnScroll: Bool {
        didSet {
            if minimizesTabBarOnScroll != oldValue { store.set(minimizesTabBarOnScroll, for: SettingKey.tabBarMinimizesOnScroll) }
        }
    }
    /// Density: compact rows.
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
        textSizePercent = SettingKey.textSizePercent(from: store)
        compactMode = store.value(for: SettingKey.compactMode)
        minimizesTabBarOnScroll = store.value(for: SettingKey.tabBarMinimizesOnScroll)
    }

    private static func clamp(_ percent: Int) -> Int {
        min(max(percent, SettingKey.textSizePercentRange.lowerBound), SettingKey.textSizePercentRange.upperBound)
    }
}
