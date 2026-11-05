import HFRModels
import HFRStorage
import Observation

// Port of HFRswift/Swift/AppSettingsView.swift (AppSettingsView, "Général" section) @ 2440d79. Differences: the start-screen and
// default-browser rows come from master; neither exists at 2440d79 (GAP-002, 150; UXD).
/// The "Général" settings, one instance for the whole app (`SwiftHFRApp` owns it): each property reads its legacy key at
/// creation and writes it back on every change, so what the screen shows is what the store holds (LOT-119).
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
    /// In-app text size in percent, an offset on top of Dynamic Type (below 100 gives a denser display); every screen
    /// reads it as `textScale` (LOT-169).
    var textSizePercent: Int {
        didSet {
            // Whether or not the nested assignment runs this observer again, the final value is what gets stored.
            let clamped = Self.clamp(textSizePercent)
            if clamped != textSizePercent { textSizePercent = clamped }
            if textSizePercent != oldValue { store.set(textSizePercent, for: SettingKey.textSizePercent) }
        }
    }
    /// Minimise the tab bar while scrolling (`tabbar_minimize_on_scroll`, default on). Read by the root tab bar (LOT-170).
    var minimizesTabBarOnScroll: Bool {
        didSet {
            if minimizesTabBarOnScroll != oldValue { store.set(minimizesTabBarOnScroll, for: SettingKey.tabBarMinimizesOnScroll) }
        }
    }
    /// When third-party images load (`display_images`, FEAT-011): the reader reads the store on every page and image
    /// request, so a change applies to the next page (images of an open page not yet requested follow it).
    /// HFR's own images and the always-blocked hosts are unaffected (policy C).
    var imageLoading: ImageDisplayMode {
        didSet { if imageLoading != oldValue { store.set(imageLoading, for: SettingKey.displayImages) } }
    }
    /// Density: compact rows; every list reads it as `listDensity` (LOT-169).
    var compactMode: Bool {
        didSet { if compactMode != oldValue { store.set(compactMode, for: SettingKey.compactMode) } }
    }

    /// The app-wide type scale of `textSizePercent`.
    var textScale: TextScale { TextScale(percent: textSizePercent) }
    /// The list density of `compactMode`.
    var listDensity: ListDensity { ListDensity(compactMode: compactMode) }

    /// Filtrer les posts: how many times a post must be quoted to be kept (`filter_posts_min_quotes`, legacy choices 3, 4, 5,
    /// 7 and 10; a stored value of 0 or less reads as 3, as the filter does).
    var filterMinimumQuotes: Int {
        didSet {
            if filterMinimumQuotes != oldValue { store.set(filterMinimumQuotes, for: SettingKey.quoteFilterMinimumCount) }
        }
    }
    /// Filtrer les posts: keep the posts of allowlisted pseudos (`filter_posts_quotes` containing `wl`). Legacy writes
    /// `wl_pseudo` or `pseudo` (`AppSettingsView.swift:165-169`).
    var filterIncludesAllowlist: Bool {
        didSet {
            guard filterIncludesAllowlist != oldValue else { return }
            let stored: QuoteFilterExceptions = filterIncludesAllowlist ? .standard : [.mentionsOwnPseudo]
            store.set(stored, for: SettingKey.quoteFilterExceptions)
        }
    }

    /// The minimums the picker offers (legacy `filterPostsMinimumQuoteOptions`, `AppSettingsView.swift:157-163`).
    static let filterMinimumQuoteChoices = [3, 4, 5, 7, 10]

    /// The picker's choices, plus the stored value when it is none of them (a migrated setting), so the picker never shows
    /// a blank selection.
    var filterMinimumQuoteOptions: [Int] {
        Self.filterMinimumQuoteChoices.contains(filterMinimumQuotes)
            ? Self.filterMinimumQuoteChoices : (Self.filterMinimumQuoteChoices + [filterMinimumQuotes]).sorted()
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
        imageLoading = store.value(for: SettingKey.displayImages)
        minimizesTabBarOnScroll = store.value(for: SettingKey.tabBarMinimizesOnScroll)
        filterMinimumQuotes = store.value(for: SettingKey.quoteFilterMinimumCount)
        filterIncludesAllowlist = store.value(for: SettingKey.quoteFilterExceptions).contains(.allowlistedAuthors)
    }

    private static func clamp(_ percent: Int) -> Int {
        min(max(percent, SettingKey.textSizePercentRange.lowerBound), SettingKey.textSizePercentRange.upperBound)
    }
}
