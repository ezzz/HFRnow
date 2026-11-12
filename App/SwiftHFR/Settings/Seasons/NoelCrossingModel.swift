import CoreGraphics
import Foundation
import Observation
import UIKit

/// The objects that cross the screen in Noël soft and the arrival sleigh (THEMES.md §4 rule 4, §5), one for the app. It counts
/// foreground time, draws the next gap (20–90 min, never less than 20), and hands one crossing at a time to one scene, only on a
/// clear screen and with animations allowed; each crossing starts with a light haptic through `HapticFeedback`.
@MainActor
@Observable
final class NoelCrossingModel {
    /// One object crossing one scene.
    struct Crossing: Equatable, Identifiable {
        let id: Int
        let item: NoelCrossingItem
        /// The art's size, in points.
        let size: CGSize
        let path: CrossingPath
        /// The arrival sleigh (1/4 of the window height, ≤ 240 pt), played before the « Oh Oh Oh ! » alert.
        let isArrival: Bool
        /// The scene that shows it.
        let scene: UUID
        let startedAt: Date
    }

    /// The shortest and longest foreground time between two crossings (operator, 2026-10-28).
    static let minGap: TimeInterval = 20 * 60
    static let maxGap: TimeInterval = 90 * 60
    /// A crossing object's height (THEMES.md tokens `sizeSoftPt`).
    static let itemHeight: CGFloat = 64
    /// The arrival sleigh: a quarter of the window height, at most 240 pt.
    static func arrivalHeight(window: CGFloat) -> CGFloat { min(max(window, 0) / 4, 240) }

    /// The crossing on screen, in `Crossing.scene`.
    private(set) var current: Crossing?
    /// The arrival sleigh is due: it plays before the alert, which waits for it.
    private(set) var arrivalPending = false

    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private let random: any SeasonalRandom
    @ObservationIgnored private let haptics: HapticFeedback
    /// Foreground time counted before the current active stretch, since the last crossing (or the launch).
    @ObservationIgnored private var foregroundBefore: TimeInterval = 0
    /// When the app came to the foreground, nil while it is not there.
    @ObservationIgnored private var activeSince: Date?
    /// The foreground time the next crossing waits for.
    @ObservationIgnored private(set) var nextGap: TimeInterval
    @ObservationIgnored private var lastID = 0

    /// Draws the first gap: nothing crosses in the first 20 minutes of foreground time.
    init(now: @escaping @MainActor () -> Date, random: any SeasonalRandom, haptics: HapticFeedback = .live) {
        self.now = now
        self.random = random
        self.haptics = haptics
        nextGap = Self.minGap + random.unit() * (Self.maxGap - Self.minGap)
    }

    /// Foreground time since the last crossing: only the time the app was active counts.
    var foregroundTime: TimeInterval {
        foregroundBefore + (activeSince.map { max(0, now().timeIntervalSince($0)) } ?? 0)
    }

    /// The app came to the foreground (`true`) or left it; a crossing on screen stops when it leaves.
    func foregroundChanged(active: Bool) {
        if active {
            if activeSince == nil { activeSince = now() }
        } else {
            foregroundBefore = foregroundTime
            activeSince = nil
            current = nil
        }
    }

    /// The first launch of a window with animations allowed: the sleigh crosses before the alert.
    func queueArrival() { arrivalPending = true }

    /// The crossing `scene` may start now in an area of `area` (the band between the bars) of a window `windowHeight` high: the
    /// arrival sleigh when due, else an object once the gap is spent while `crossingsOn` (Noël soft). Nothing while the screen
    /// is not clear (THEMES.md §4 rule 5), while another crossing plays, or without animations (the arrival is then dropped,
    /// so the alert comes alone).
    func crossing(
        for scene: UUID, area: CGSize, windowHeight: CGFloat, screen: SeasonalThemeModel.ScreenState,
        animationsAllowed: Bool, crossingsOn: Bool
    ) -> Crossing? {
        if let current { return current.scene == scene ? current : nil }
        guard animationsAllowed else {
            arrivalPending = false
            return nil
        }
        guard screen.allowsAlert, activeSince != nil else { return nil }
        if arrivalPending {
            arrivalPending = false
            let size = NoelCrossingItem.sleigh.size(height: Self.arrivalHeight(window: windowHeight))
            return start(.sleigh, size: size, area: area, scene: scene, arrival: true, duration: CrossingPath.maxDuration)
        }
        guard crossingsOn, foregroundTime >= nextGap else { return nil }
        let items = NoelCrossingItem.crossing
        let item = items[min(Int(random.unit() * Double(items.count)), items.count - 1)]
        let duration = 2.2 + 0.8 * random.unit()
        return start(item, size: item.size(height: Self.itemHeight), area: area, scene: scene, arrival: false, duration: duration)
    }

    /// `scene`'s screen changed: a crossing stops as soon as the keyboard, a sheet, an alert or the lock comes up.
    func screenChanged(for scene: UUID, screen: SeasonalThemeModel.ScreenState) {
        if current?.scene == scene, !screen.allowsAlert { current = nil }
    }

    /// The crossing `id` reached the far edge, or was tapped away (THEMES.md §4 rule 3).
    func finish(_ id: Int) {
        if current?.id == id { current = nil }
    }

    /// `scene` went away: its crossing stops.
    func release(scene: UUID) {
        if current?.scene == scene { current = nil }
    }

    private func start(
        _ item: NoelCrossingItem, size: CGSize, area: CGSize, scene: UUID, arrival: Bool, duration: TimeInterval
    ) -> Crossing? {
        guard let path = CrossingPath.random(
            in: area, objectSize: size, directional: item.isDirectional, horizontalOnly: item == .sleigh,
            maxTilt: item == .sleigh ? .pi / 12 : .pi / 6, duration: duration, random: random
        ) else { return nil }
        // The gap restarts with the crossing: the next one waits at least 20 minutes of foreground time.
        let date = now()
        foregroundBefore = 0
        activeSince = date
        nextGap = Self.minGap + random.unit() * (Self.maxGap - Self.minGap)
        lastID += 1
        let crossing = Crossing(
            id: lastID, item: item, size: size, path: path, isArrival: arrival, scene: scene, startedAt: date
        )
        current = crossing
        haptics.impact(.light)
        return crossing
    }
}
