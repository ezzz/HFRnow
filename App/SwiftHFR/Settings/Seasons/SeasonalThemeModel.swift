import Foundation
import HFRModels
import HFRStorage
import Observation
import UIKit

// Port of Classes/HFRplusAppDelegate.m (applicationDidBecomeActive: noel_first_time_2022, theme_noel_disabled, the alert) and
// Classes/PlusSettingsViewController.m (theme_noel_period cell, `:112-115`) @ 87fe0d1c. Differences (GAP-147): a window every
// year; Noël soft is switched on once per season, the user's theme is saved and restored, « Désactiver » opts out for the
// year; packing at the end; legacy forced the theme off at every launch (`:103`, `:365`), so it never showed.
/// The seasonal scheduler (THEMES.md §5), one for the app: at each scene activation it switches the soft theme of a family on
/// (Noël soft, Spooktober soft, LOT-191), shows the arrival, packs or restores, from the date of `now` in the Gregorian calendar
/// of `timeZone`. State lives in the device-only `season.*` keys of `store`, one set per family and season.
@MainActor
@Observable
final class SeasonalThemeModel {
    /// What an activation did, for the animations (sleigh, elves) and for tests.
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
        /// « Thème de Noël activé » (or « Thème de Noël » when nothing was switched on) [OK] [Désactiver].
        case noelArrival(year: Int)
        /// « Spooktober est là ! » [OK] [Désactiver] (LOT-191).
        case samainArrival(year: Int)

        /// The alert's message.
        var message: String { "Thème disponible dans les réglages" }

        /// The family whose arrival it is, and its season.
        var family: SeasonFamily {
            switch self {
            case .noelArrival: .noel
            case .samainArrival: .samain
            }
        }

        var year: Int {
            switch self {
            case let .noelArrival(year), let .samainArrival(year): year
            }
        }

        /// The arrival alert of `family`'s season `year`.
        static func arrival(of family: SeasonFamily, year: Int) -> Alert {
            switch family {
            case .noel: .noelArrival(year: year)
            case .samain: .samainArrival(year: year)
            }
        }

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
    /// The family whose window today is in: the « Thèmes de saison » section shows and its themes can be picked.
    private(set) var selectableFamily: SeasonFamily?
    /// Today is inside a seasonal window.
    var isSelectable: Bool { selectableFamily != nil }
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
    /// The seasonal theme drawn: the active one, or the one the elves are still packing (PR 3), already restored in the store.
    var drawnTheme: SeasonalTheme? { activeTheme ?? packing.current?.theme }
    /// Snow falls: Noël soft is drawn and animations are allowed (static snow stays otherwise).
    var snowFalls: Bool { drawnTheme == .noelSoft && animationsAllowed }

    /// The arrival sleigh and the objects crossing Noël soft (PR 2).
    @ObservationIgnored let crossings: NoelCrossingModel
    /// The elves of the packing (PR 3).
    @ObservationIgnored let packing: NoelPackingModel
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
        crossings: NoelCrossingModel? = nil,
        packing: NoelPackingModel? = nil
    ) {
        self.crossings = crossings ?? NoelCrossingModel(now: now, random: SystemSeasonalRandom())
        self.packing = packing ?? NoelPackingModel(now: now)
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
        let events = SeasonFamily.allCases.flatMap { activate($0, on: date) }
        refresh()
        return events
    }

    /// One family's part of an activation (see `sceneDidBecomeActive`): at most one family is inside its window at a time.
    private func activate(_ family: SeasonFamily, on date: Date) -> [Event] {
        let year = family.seasonYear(of: date, in: calendar)
        var events: [Event] = []
        // A theme of another season: left on by an app not opened since its window, however long ago, or switched on under a
        // clock that ran ahead and was set back. Restored first, so two saved themes never coexist.
        if let active = store.value(for: family.activeYear), active != year {
            restore(family, year: active)
            events.append(.restoredSilently(year: active))
        }
        let phase = family.phase(of: date, in: calendar)
        // Elves still waiting for a clear screen when the packing days are over: the theme they would take down goes now.
        if phase != .packing, packing.current?.theme.family == family, !packing.isPlaying { packing.finish() }
        // An arrival nobody answered before its window closed is dropped.
        if !phase.isSelectable { store.reset(family.arrivalPending(year: year)) }
        if let event = event(for: phase, of: family, year: year) { events.append(event) }
        return events
    }

    /// Samain overlays still waiting for a clear screen when their window closes with the app in the foreground (midnight on 07/11
    /// behind the keyboard, or on 31/10 behind a sheet): the witch and the arrival are dropped, with the alert that would name
    /// « Spooktober est là ! » a day late. The layers ask before they start one. Noël's own is #1440's follow-up, not changed here.
    func dropOverlaysOutOfSeason() {
        let family = SeasonFamily.samain
        let date = now()
        let phase = family.phase(of: date, in: calendar)
        if phase != .packing, packing.current?.theme.family == family, !packing.isPlaying { packing.finish() }
        guard !phase.isSelectable else { return }
        let pending = family.arrivalPending(year: family.seasonYear(of: date, in: calendar))
        guard store.value(for: pending) else { return }
        store.reset(pending)
        crossings.dropArrival(ifItems: family.arrivalItems)
        refresh()
    }

    /// What the first activation of `phase` does for `family`'s season `year`, if anything.
    private func event(for phase: NoelCalendar.Phase, of family: SeasonFamily, year: Int) -> Event? {
        switch phase {
        case .switchOn, .arrivalOnly:
            return arrive(family, year: year, switching: phase == .switchOn)
        case .packing where isOn(family, year: year):
            let first = !store.value(for: family.packingShown(year: year))
            store.set(true, for: family.packingShown(year: year))
            // The store is restored now; the theme stays drawn until the elves have taken it down.
            if first, animationsAllowed { packing.queue(year: year, theme: onTheme(family, year: year)) }
            restore(family, year: year)
            let packed: Event = first ? .packed(year: year, animated: animationsAllowed) : .restoredSilently(year: year)
            return packed
        case .outside where isOn(family, year: year):
            restore(family, year: year)
            return .restoredSilently(year: year)
        default:
            return nil
        }
    }

    /// The first activation of a window, once per season: the arrival is stored as pending until answered, and the family's soft
    /// theme is switched on when `switching` (Noël: 01/12–24/12, Samain: all of October), automatic themes are on and the season
    /// is not opted out.
    private func arrive(_ family: SeasonFamily, year: Int, switching: Bool) -> Event? {
        guard !store.value(for: family.arrivalShown(year: year)) else { return nil }
        store.set(true, for: family.arrivalShown(year: year))
        store.set(true, for: family.arrivalPending(year: year))
        let switched = switching && isAutomatic && !store.value(for: family.optedOut(year: year)) && !isOn(family, year: year)
        if switched { switchOn(family, year: year, theme: family.defaultTheme) }
        if animationsAllowed { crossings.queueArrival(items: family.arrivalItems) }
        return .arrival(year: year, switchedOn: switched, sleigh: animationsAllowed)
    }

    /// The alert's title: it names the situation (HIG › Alerts, #1174), so « activé » only when a Noël theme really is on (not on
    /// 25–26/12, with automatic themes off, or after the user picked another theme before the alert came). Spooktober's is the
    /// operator's sentence, true whether or not a theme was switched on.
    func title(for alert: Alert) -> String {
        switch alert {
        case .noelArrival: activeTheme != nil ? "Thème de Noël activé" : "Thème de Noël"
        case .samainArrival: "Spooktober est là !"
        }
    }

    /// The answer to the arrival alert: « Désactiver » restores the previous theme and opts out for the season; « OK » keeps it.
    func answerArrival(disable: Bool) {
        guard let alert = pendingAlert else { return }
        store.reset(alert.family.arrivalPending(year: alert.year))
        alertScene = nil
        if disable {
            store.set(true, for: alert.family.optedOut(year: alert.year))
            restore(alert.family, year: alert.year)
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

    /// A pick in Réglages › Thème: a seasonal theme inside its window, or nil for the user's own theme. Moving from one theme of
    /// a family to the other keeps the theme saved when the first was switched on.
    func select(_ theme: SeasonalTheme?) {
        let date = now()
        guard let theme else {
            for family in SeasonFamily.allCases {
                let year = family.seasonYear(of: date, in: calendar)
                if isOn(family, year: year) { restore(family, year: year) }
            }
            refresh()
            return
        }
        let family = theme.family
        let year = family.seasonYear(of: date, in: calendar)
        guard family.phase(of: date, in: calendar).isSelectable else { return }
        if isOn(family, year: year) {
            store.set(theme.rawValue, for: family.themeID(year: year))
        } else {
            switchOn(family, year: year, theme: theme)
        }
        refresh()
    }

    /// Season dates and years are Gregorian whatever the device's calendar (a Buddhist year would name other keys), in the time
    /// zone of the moment, so a zone change during a run is followed.
    private var calendar: Calendar { NoelCalendar.gregorian(in: timeZone()) }

    private func isOn(_ family: SeasonFamily, year: Int) -> Bool {
        store.value(for: family.previousThemeID(year: year)) != nil
    }

    /// Gives the user's theme back. A seasonal theme never writes the "Thème" keys, so restoring is dropping the saved id; it
    /// never writes `theme_id` either, so a theme picked during the season stays (operator decision (a), 2026-11-12).
    private func restore(_ family: SeasonFamily, year: Int) {
        store.reset(family.previousThemeID(year: year))
        store.reset(family.themeID(year: year))
        if store.value(for: family.activeYear) == year { store.reset(family.activeYear) }
    }

    /// Saves the current theme (LOT-188's stored `theme_id`, Legacy when none), names the seasonal theme now on and points at the
    /// season, so any later activation can find and restore it. Restoring drops the saved id: the overlay never writes
    /// `theme_id`, so the user's theme is back as it was; a saved "legacy" from the first build reads the same.
    private func switchOn(_ family: SeasonFamily, year: Int, theme: SeasonalTheme) {
        store.set(store.value(for: SettingKey.themeID) ?? ThemeDefinition.legacyID, for: family.previousThemeID(year: year))
        store.set(theme.rawValue, for: family.themeID(year: year))
        store.set(year, for: family.activeYear)
    }

    /// The theme of `family` and season `year` that is on: the stored one; none stored (every build before PR 4) or an id this
    /// build does not know reads as the family's soft theme.
    private func onTheme(_ family: SeasonFamily, year: Int) -> SeasonalTheme {
        let stored = store.value(for: family.themeID(year: year)).flatMap(SeasonalTheme.init(rawValue:))
        return stored.flatMap { $0.family == family ? $0 : nil } ?? family.defaultTheme
    }

    private func refresh() {
        let date = now()
        var theme: SeasonalTheme?
        var alert: Alert?
        var selectable: SeasonFamily?
        for family in SeasonFamily.allCases {
            let year = family.seasonYear(of: date, in: calendar)
            let phase = family.phase(of: date, in: calendar)
            if phase.isSelectable {
                selectable = family
                if store.value(for: family.arrivalPending(year: year)) { alert = .arrival(of: family, year: year) }
            }
            // Outside the window a theme left on is about to be restored: never draw it, even for the first frame.
            if phase != .outside, isOn(family, year: year) { theme = onTheme(family, year: year) }
        }
        selectableFamily = selectable
        pendingAlert = alert
        activeTheme = theme
    }
}
