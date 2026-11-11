import Foundation
import HFRStorage
import Observation
import UIKit

// Port of Classes/HFRplusAppDelegate.m (applicationDidBecomeActive: noel_first_time_2022, theme_noel_disabled, the alert) and
// Classes/PlusSettingsViewController.m (theme_noel_period cell, `:112-115`) @ 87fe0d1c. Differences (GAP-147): a window every
// year; Noël soft is switched on once per season, the user's theme is saved and restored, « Désactiver » opts out for the
// year; packing at the end; legacy forced the theme off at every launch (`:103`, `:365`), so it never showed.
/// The seasonal scheduler (THEMES.md §5), one for the app: at each scene activation it switches Noël soft on, shows the arrival,
/// packs or restores, from the date of `now` in `calendar`. State lives in the device-only `season.*` keys of `store`.
@MainActor
@Observable
final class SeasonalThemeModel {
    /// What an activation did, for the animations of later PRs (sleigh, elves) and for tests.
    enum Event: Equatable {
        /// First launch of the window: `switchedOn` when Noël soft was turned on; `sleigh` when the sleigh may cross.
        case arrival(year: Int, switchedOn: Bool, sleigh: Bool)
        /// First launch 27/12–02/01 with a Noël theme on: restored; `animated` when the elves may play.
        case packed(year: Int, animated: Bool)
        /// A Noël theme left on after its packing days, restored without a word.
        case restoredSilently(year: Int)
    }

    /// The alert to show once nothing covers the screen.
    enum Alert: Hashable, Identifiable {
        /// « Oh Oh Oh ! » [OK] [Désactiver].
        case noelArrival(year: Int)

        var id: Self { self }
    }

    /// The theme a seasonal theme replaces today: the one look the app has until the theme engine (LOT-188) gives it an id.
    static let legacyThemeID = "legacy"

    /// The seasonal theme drawn over the "Thème" settings, or nil.
    private(set) var activeTheme: SeasonalTheme?
    /// The arrival alert waiting to be shown.
    private(set) var pendingAlert: Alert?
    /// Today is inside a Noël window: the « Thèmes de saison » section shows and Noël soft can be picked.
    private(set) var isSelectable = false
    /// « Thèmes de saison automatiques ».
    var isAutomatic: Bool {
        didSet { if isAutomatic != oldValue { store.set(isAutomatic, for: SettingKey.seasonalThemesAutomatic) } }
    }
    /// « Animations de saison ».
    var animationsEnabled: Bool {
        didSet { if animationsEnabled != oldValue { store.set(animationsEnabled, for: SettingKey.seasonalAnimations) } }
    }

    /// Animations may play: the setting is on and Reduce Motion is off (THEMES.md §4 rules 1–2).
    var animationsAllowed: Bool { animationsEnabled && !reduceMotion() }
    /// Snow falls: Noël soft is on and animations are allowed (static snow stays otherwise).
    var snowFalls: Bool { activeTheme == .noelSoft && animationsAllowed }

    @ObservationIgnored private let store: any SettingsStore
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let reduceMotion: @MainActor () -> Bool

    /// Reads the state of today's season; writes nothing until the first activation.
    init(
        store: any SettingsStore,
        now: @escaping @MainActor () -> Date = { Date() },
        calendar: Calendar = .autoupdatingCurrent,
        reduceMotion: @escaping @MainActor () -> Bool = { UIAccessibility.isReduceMotionEnabled }
    ) {
        self.store = store
        self.now = now
        self.calendar = calendar
        self.reduceMotion = reduceMotion
        isAutomatic = store.value(for: SettingKey.seasonalThemesAutomatic)
        animationsEnabled = store.value(for: SettingKey.seasonalAnimations)
        refresh()
    }

    /// The scene became active: the first one of a window plays the arrival or the packing, once per season.
    @discardableResult
    func sceneDidBecomeActive() -> [Event] {
        let date = now()
        let year = NoelCalendar.seasonYear(of: date, in: calendar)
        var events: [Event] = []
        // Last season's theme, left on by an app not opened since its window.
        if isOn(year: year - 1) {
            restore(year: year - 1)
            events.append(.restoredSilently(year: year - 1))
        }
        switch NoelCalendar.phase(of: date, in: calendar) {
        case let phase where phase.isSelectable:
            guard !store.value(for: SettingKey.noelArrivalShown(year: year)) else { break }
            store.set(true, for: SettingKey.noelArrivalShown(year: year))
            let switchOn = phase == .switchOn && isAutomatic && !store.value(for: SettingKey.noelOptedOut(year: year))
                && !isOn(year: year)
            if switchOn { store.set(Self.legacyThemeID, for: SettingKey.noelPreviousThemeID(year: year)) }
            pendingAlert = .noelArrival(year: year)
            events.append(.arrival(year: year, switchedOn: switchOn, sleigh: animationsAllowed))
        case .packing where isOn(year: year):
            let first = !store.value(for: SettingKey.noelPackingShown(year: year))
            store.set(true, for: SettingKey.noelPackingShown(year: year))
            restore(year: year)
            events.append(first ? .packed(year: year, animated: animationsAllowed) : .restoredSilently(year: year))
        case .outside where isOn(year: year):
            restore(year: year)
            events.append(.restoredSilently(year: year))
        default:
            break
        }
        refresh()
        return events
    }

    /// The answer to the arrival alert: « Désactiver » restores the previous theme and opts out for the season; « OK » keeps it.
    func answerArrival(disable: Bool) {
        guard case let .noelArrival(year) = pendingAlert else { return }
        pendingAlert = nil
        guard disable else { return }
        store.set(true, for: SettingKey.noelOptedOut(year: year))
        restore(year: year)
        refresh()
    }

    /// A pick in Réglages › Thème: a seasonal theme inside its window, or nil for the user's own theme.
    func select(_ theme: SeasonalTheme?) {
        let date = now()
        let year = NoelCalendar.seasonYear(of: date, in: calendar)
        if theme == nil {
            if isOn(year: year) { restore(year: year) }
        } else if NoelCalendar.phase(of: date, in: calendar).isSelectable, !isOn(year: year) {
            store.set(Self.legacyThemeID, for: SettingKey.noelPreviousThemeID(year: year))
        }
        refresh()
    }

    private func isOn(year: Int) -> Bool {
        store.value(for: SettingKey.noelPreviousThemeID(year: year)) != nil
    }

    /// Gives the saved theme back. Noël soft never wrote the "Thème" keys, so restoring is dropping the saved id; with the theme
    /// engine (LOT-188) it will write the saved id back to the theme key.
    private func restore(year: Int) {
        store.reset(SettingKey.noelPreviousThemeID(year: year))
    }

    private func refresh() {
        let date = now()
        let year = NoelCalendar.seasonYear(of: date, in: calendar)
        let phase = NoelCalendar.phase(of: date, in: calendar)
        isSelectable = phase.isSelectable
        // Outside the window a theme left on is about to be restored: never draw it, even for the first frame.
        activeTheme = phase != .outside && isOn(year: year) ? .noelSoft : nil
    }
}
