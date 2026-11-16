import Foundation
import HFRModels
import HFRStorage
import Observation
import UIKit

// Port of Classes/HFRplusAppDelegate.m (applicationDidBecomeActive: noel_first_time_2022, theme_noel_disabled, the alert) and
// Classes/PlusSettingsViewController.m (theme_noel_period cell, `:112-115`) @ 87fe0d1c. Differences (GAP-147): a window every
// year; Noël soft is switched on once per season, the user's theme is saved and restored, « Désactiver » opts out for the
// year; packing at the end; legacy forced the theme off at every launch (`:103`, `:365`), so it never showed.
/// The seasonal scheduler (THEMES.md §5), one for the app: at each scene activation it switches Noël soft on, shows the arrival,
/// packs or restores, from the date of `now` in the Gregorian calendar of `timeZone`. State lives in the device-only
/// `season.*` keys of `store`.
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

    /// What the screen shows besides the app's own views: the arrival alert waits while any of it is up (THEMES.md §4 rule 5).
    nonisolated struct ScreenState: Equatable, Sendable {
        /// The app lock covers the screen.
        var isCovered = false
        /// A sheet, the composer, a full-screen cover or another alert is presented.
        var isPresenting = false
        /// The keyboard is up.
        var isKeyboardVisible = false

        /// Nothing stands in the way of the alert.
        var allowsAlert: Bool { !isCovered && !isPresenting && !isKeyboardVisible }
    }

    /// The seasonal theme drawn over the "Thème" settings, or nil.
    private(set) var activeTheme: SeasonalTheme?
    /// The arrival alert waiting for an answer; stored, so a kill before it is seen shows it again at the next launch.
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

    /// The arrival sleigh and the objects crossing Noël soft (PR 2).
    @ObservationIgnored let crossings: NoelCrossingModel
    @ObservationIgnored private let store: any SettingsStore
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private let timeZone: @MainActor () -> TimeZone
    @ObservationIgnored private let reduceMotion: @MainActor () -> Bool
    /// The scene showing the arrival alert: with two windows (iPad) only one presents it.
    @ObservationIgnored private var alertScene: UUID?

    /// Reads the state of today's season; writes nothing until the first activation.
    init(
        store: any SettingsStore,
        now: @escaping @MainActor () -> Date = { Date() },
        timeZone: @escaping @MainActor () -> TimeZone = { .autoupdatingCurrent },
        reduceMotion: @escaping @MainActor () -> Bool = { UIAccessibility.isReduceMotionEnabled },
        crossings: NoelCrossingModel? = nil
    ) {
        self.crossings = crossings ?? NoelCrossingModel(now: now, random: SystemSeasonalRandom())
        self.store = store
        self.now = now
        self.timeZone = timeZone
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
        // A theme of another season: left on by an app not opened since its window, however long ago, or switched on under a
        // clock that ran ahead and was set back. Restored first, so two saved themes never coexist.
        if let active = store.value(for: SettingKey.noelActiveYear), active != year {
            restore(year: active)
            events.append(.restoredSilently(year: active))
        }
        let phase = NoelCalendar.phase(of: date, in: calendar)
        // An arrival nobody answered before its window closed is dropped.
        if !phase.isSelectable { store.reset(SettingKey.noelArrivalPending(year: year)) }
        switch phase {
        case .switchOn, .arrivalOnly:
            if let arrival = arrive(year: year, switching: phase == .switchOn) { events.append(arrival) }
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

    /// The first activation of a window, once per season: the arrival is stored as pending until answered, and Noël soft is
    /// switched on when `switching` (01/12–24/12), automatic themes are on and the season is not opted out.
    private func arrive(year: Int, switching: Bool) -> Event? {
        guard !store.value(for: SettingKey.noelArrivalShown(year: year)) else { return nil }
        store.set(true, for: SettingKey.noelArrivalShown(year: year))
        store.set(true, for: SettingKey.noelArrivalPending(year: year))
        let switched = switching && isAutomatic && !store.value(for: SettingKey.noelOptedOut(year: year)) && !isOn(year: year)
        if switched { switchOn(year: year) }
        if animationsAllowed { crossings.queueArrival() }
        return .arrival(year: year, switchedOn: switched, sleigh: animationsAllowed)
    }

    /// The answer to the arrival alert: « Désactiver » restores the previous theme and opts out for the season; « OK » keeps it.
    func answerArrival(disable: Bool) {
        guard case let .noelArrival(year) = pendingAlert else { return }
        store.reset(SettingKey.noelArrivalPending(year: year))
        alertScene = nil
        if disable {
            store.set(true, for: SettingKey.noelOptedOut(year: year))
            restore(year: year)
        }
        refresh()
    }

    /// The alert `scene` may present now: the pending one, when `screen` allows it and no other scene shows it.
    func alert(for scene: UUID, screen: ScreenState) -> Alert? {
        guard let pendingAlert, alertScene == nil || alertScene == scene else { return nil }
        // The sleigh crosses first (THEMES.md §5).
        guard !crossings.arrivalPending, crossings.current?.isArrival != true else { return nil }
        // A scene that already shows it keeps it; the others wait for a clear screen.
        guard alertScene == scene || screen.allowsAlert else { return nil }
        alertScene = scene
        return pendingAlert
    }

    /// `scene` went away without an answer: another scene, or the next launch, shows the alert.
    func releaseAlert(for scene: UUID) {
        if alertScene == scene { alertScene = nil }
    }

    /// A pick in Réglages › Thème: a seasonal theme inside its window, or nil for the user's own theme.
    func select(_ theme: SeasonalTheme?) {
        let date = now()
        let year = NoelCalendar.seasonYear(of: date, in: calendar)
        if theme == nil {
            if isOn(year: year) { restore(year: year) }
        } else if NoelCalendar.phase(of: date, in: calendar).isSelectable, !isOn(year: year) {
            switchOn(year: year)
        }
        refresh()
    }

    /// Season dates and years are Gregorian whatever the device's calendar (a Buddhist year would name other keys), in the time
    /// zone of the moment, so a zone change during a run is followed.
    private var calendar: Calendar { NoelCalendar.gregorian(in: timeZone()) }

    private func isOn(year: Int) -> Bool {
        store.value(for: SettingKey.noelPreviousThemeID(year: year)) != nil
    }

    /// Gives the user's theme back. Noël soft never writes the "Thème" keys, so restoring is dropping the saved id; it never
    /// writes `theme_id` either, so a theme picked during the season stays (operator decision (a), 2026-11-12).
    private func restore(year: Int) {
        store.reset(SettingKey.noelPreviousThemeID(year: year))
        if store.value(for: SettingKey.noelActiveYear) == year { store.reset(SettingKey.noelActiveYear) }
    }

    /// Saves the current theme (LOT-188's stored `theme_id`, Legacy when none) and points at the season, so any later activation
    /// can find and restore it. Restoring drops the saved id: the overlay never writes `theme_id`, so the user's theme is back
    /// as it was; a saved "legacy" from the first build reads the same.
    private func switchOn(year: Int) {
        store.set(store.value(for: SettingKey.themeID) ?? ThemeDefinition.legacyID, for: SettingKey.noelPreviousThemeID(year: year))
        store.set(year, for: SettingKey.noelActiveYear)
    }

    private func refresh() {
        let date = now()
        let year = NoelCalendar.seasonYear(of: date, in: calendar)
        let phase = NoelCalendar.phase(of: date, in: calendar)
        isSelectable = phase.isSelectable
        pendingAlert = phase.isSelectable && store.value(for: SettingKey.noelArrivalPending(year: year)) ? .noelArrival(year: year) : nil
        // Outside the window a theme left on is about to be restored: never draw it, even for the first frame.
        activeTheme = phase != .outside && isOn(year: year) ? .noelSoft : nil
    }
}
