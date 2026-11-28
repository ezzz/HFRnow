import Foundation
import HFRStorage
import Observation

/// The 14 July of THEMES.md §5 on local dates: Gregorian whatever the device's calendar, in the zone of the moment.
enum FeteNationaleCalendar {
    /// `date` is the 14th of July in `calendar`'s time zone.
    static func isFeteNationale(_ date: Date, in calendar: Calendar) -> Bool {
        let parts = NoelCalendar.gregorian(in: calendar.timeZone).dateComponents([.month, .day], from: date)
        return parts.month == 7 && parts.day == 14
    }

    /// The Gregorian year of `date`: the key of the day's overlay.
    static func year(of date: Date, in calendar: Calendar) -> Int {
        NoelCalendar.gregorian(in: calendar.timeZone).component(.year, from: date)
    }
}

// New, no legacy counterpart @ 87fe0d1c (GAP row of LOT-194, class b·operator). Same model as `NoelPackingModel` (LOT-166).
/// The 14 July overlay (THEMES.md §5), one for the app: on the first activation of the day, with animations allowed, a bust of
/// Marianne and fireworks play for `duration` in one active scene, on a clear screen (rule 5), once per year and device. Without
/// animations (Reduce Motion, « Animations de saison » off) nothing is queued and the day counts as seen.
@MainActor
@Observable
final class FeteNationaleModel {
    /// One overlay, waiting for a clear screen or playing in `scene`.
    struct Show: Equatable {
        /// The year of the 14 July.
        let year: Int
        /// The scene playing it; nil while it waits.
        var scene: UUID?
        /// « Fête nationale » was announced to VoiceOver, by whichever scene played it.
        var announced = false
    }

    /// How long it plays: 3–5 s (THEMES.md §4 rule 3).
    static let duration: TimeInterval = 4
    /// Cut this soon after it started (an alert of the same launch, a window resized away) it waits and plays again, at most
    /// `maxReplays` times; cut later, it is over.
    static let replayWindow: TimeInterval = 1
    static let maxReplays = 2

    /// The overlay waiting or playing; nil once done.
    private(set) var current: Show?
    /// The overlay is on screen.
    var isPlaying: Bool { current?.scene != nil }

    /// The overlay plays in `scene` now.
    func isPlaying(in scene: UUID) -> Bool { current?.scene == scene }

    @ObservationIgnored private let store: any SettingsStore
    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private let timeZone: @MainActor () -> TimeZone
    /// The scenes active now: only one of them plays the overlay (iPad: another window's phase never ends it).
    @ObservationIgnored private var activeScenes: Set<UUID> = []
    @ObservationIgnored private var startedAt: Date?
    @ObservationIgnored private var replays = 0

    /// A model on `store` and the clock `now` (the tests move it by hand).
    init(
        store: any SettingsStore, now: @escaping @MainActor () -> Date = { Date() },
        timeZone: @escaping @MainActor () -> TimeZone = { .autoupdatingCurrent }
    ) {
        self.store = store
        self.now = now
        self.timeZone = timeZone
    }

    /// A scene became active: the first activation of the 14th, once per year, queues the overlay when animations are allowed.
    /// Any other day drops an overlay still waiting for a clear screen.
    func sceneDidBecomeActive(animationsAllowed: Bool) {
        guard isFeteNationale(now()) else {
            if !isPlaying { current = nil }
            return
        }
        let calendar = NoelCalendar.gregorian(in: timeZone())
        let year = FeteNationaleCalendar.year(of: now(), in: calendar)
        guard !store.value(for: SettingKey.feteNationaleShown(year: year)) else { return }
        store.set(true, for: SettingKey.feteNationaleShown(year: year))
        guard animationsAllowed else { return }
        current = Show(year: year)
        replays = 0
    }

    /// `scene` became active (`true`) or left. The overlay playing there stops when it leaves (replayed if it had only begun).
    func sceneChanged(_ scene: UUID, active: Bool) {
        if active {
            activeScenes.insert(scene)
        } else {
            activeScenes.remove(scene)
            guard current?.scene == scene else { return }
            if canReplay { replay() } else { current = nil }
        }
    }

    /// The overlay `scene` may play now: the one it already plays, or the waiting one once `scene` is active, `screen` is clear
    /// and no other scene plays it. Animations turned off before it played drop it.
    func start(for scene: UUID, screen: SeasonalThemeModel.ScreenState, animationsAllowed: Bool) -> Show? {
        guard let current else { return nil }
        // Waiting behind the keyboard past midnight: the day is over, the overlay is dropped (not while it plays).
        if current.scene == nil, !isFeteNationale(now()) {
            self.current = nil
            return nil
        }
        if let playing = current.scene { return playing == scene ? current : nil }
        guard animationsAllowed else {
            self.current = nil
            return nil
        }
        guard activeScenes.contains(scene), screen.allowsAlert else { return nil }
        self.current?.scene = scene
        startedAt = now()
        return self.current
    }

    /// `scene`'s screen changed: the overlay stops as soon as the keyboard, a sheet, an alert or the lock comes up (rule 5); in
    /// its first second it waits to play again, later it is over.
    func screenChanged(for scene: UUID, screen: SeasonalThemeModel.ScreenState) {
        guard !screen.allowsAlert, isPlaying(in: scene) else { return }
        if canReplay { replay() } else { current = nil }
    }

    /// The words are to be announced now: true once per overlay, whichever scene plays it and however often it is replayed
    /// (rule 6: the overlay is hidden, its sentence is spoken once).
    func shouldAnnounce() -> Bool {
        guard let current, !current.announced else { return false }
        self.current?.announced = true
        return true
    }

    /// The overlay played to its end on a clear screen, or was tapped away.
    func finish() {
        current = nil
    }

    /// `scene` went away while it played: the overlay stops, as when it leaves.
    func release(scene: UUID) {
        sceneChanged(scene, active: false)
    }

    /// `date` is the 14th of July in the zone of the moment.
    private func isFeteNationale(_ date: Date) -> Bool {
        FeteNationaleCalendar.isFeteNationale(date, in: NoelCalendar.gregorian(in: timeZone()))
    }

    private var canReplay: Bool {
        guard let startedAt else { return false }
        return now().timeIntervalSince(startedAt) < Self.replayWindow && replays < Self.maxReplays
    }

    private func replay() {
        replays += 1
        current?.scene = nil
    }
}
