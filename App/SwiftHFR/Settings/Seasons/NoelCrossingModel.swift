import CoreGraphics
import Foundation
import Observation
import UIKit

/// The objects that cross the screen in Noël soft and Spooktober soft and the arrival item (the sleigh; a witch, a ghost, a bat or
/// a vampire for Samain) (THEMES.md §4 rule 4, §5), one for the app. It counts
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
        /// The arrival item (1/4 of the window height, ≤ 240 pt), played before the arrival alert.
        let isArrival: Bool
        /// The lightning's five flashes; empty for an object that travels.
        var flashes: [LightningFlash] = []
        /// The scene that shows it.
        let scene: UUID
    }

    /// The shortest and longest foreground time between two crossings (operator, 2026-10-28).
    static let minGap: TimeInterval = 20 * 60
    static let maxGap: TimeInterval = 90 * 60
    /// A crossing object's height (THEMES.md tokens `sizeSoftPt`).
    static let itemHeight: CGFloat = 64
    /// The arrival sleigh: a quarter of the window height, at most 240 pt.
    static func arrivalHeight(window: CGFloat) -> CGFloat { min(max(window, 0) / 4, 240) }

    /// The arrival item's size: the same height, and for art wider than tall (a bat, a witch) no wider than 80 % of the area.
    static func arrivalSize(of item: NoelCrossingItem, window: CGFloat, areaWidth: CGFloat) -> CGSize {
        let height = arrivalHeight(window: window)
        guard item != .sleigh, areaWidth > 0 else { return item.size(height: height) }
        return item.size(height: min(height, areaWidth * 0.8 / item.aspectRatio))
    }

    /// The crossing on screen, in `Crossing.scene`.
    private(set) var current: Crossing?
    /// The arrival item is due: it plays before the alert, which waits for it.
    private(set) var arrivalPending = false
    /// What may play as the arrival: one of these, at random (the sleigh by default).
    @ObservationIgnored private var arrivalItems: [NoelCrossingItem] = [.sleigh]

    @ObservationIgnored private let now: @MainActor () -> Date
    @ObservationIgnored private let random: any SeasonalRandom
    @ObservationIgnored private let haptics: HapticFeedback
    /// Foreground time counted before the current active stretch, since the last crossing (or the launch).
    @ObservationIgnored private var foregroundBefore: TimeInterval = 0
    /// When the app came to the foreground (its first scene became active), nil while no scene is active.
    @ObservationIgnored private var activeSince: Date?
    /// The scenes active now: foreground time runs while any is, and a scene gets a crossing only while it is.
    @ObservationIgnored private var activeScenes: Set<UUID> = []
    /// The foreground time the next crossing waits for.
    @ObservationIgnored private(set) var nextGap: TimeInterval
    @ObservationIgnored private var lastID = 0
    /// When the current arrival sleigh first started; it is queued again when cut only within `arrivalReplayWindow` of it.
    @ObservationIgnored private var arrivalFirstStart: Date?

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

    /// `scene` became active (`true`) or left: each scene reports its own phase, so another window going to the background
    /// (iPad) neither stops this scene's crossing nor the foreground count while one scene is still active. A crossing stops
    /// when its own scene leaves.
    func sceneChanged(_ scene: UUID, active: Bool) {
        let wasForeground = !activeScenes.isEmpty
        if active {
            activeScenes.insert(scene)
        } else {
            activeScenes.remove(scene)
            if current?.scene == scene { current = nil }
        }
        if !activeScenes.isEmpty, !wasForeground {
            activeSince = now()
        } else if activeScenes.isEmpty, wasForeground {
            foregroundBefore = foregroundTime
            activeSince = nil
        }
    }

    /// The first launch of a window with animations allowed: one of `items` crosses before the alert.
    func queueArrival(items: [NoelCrossingItem] = [.sleigh]) {
        arrivalItems = items.isEmpty ? [.sleigh] : items
        arrivalPending = true
        arrivalFirstStart = nil
    }

    /// How long after its first start a cut arrival sleigh is played again: a bound in time, not a count, so the many sizes of
    /// one split-view divider drag or Stage Manager resize cannot use it up at once (#840 round 3), and constant resizes still
    /// cannot hold the alert back for ever.
    static let arrivalReplayWindow: TimeInterval = 15

    /// `scene`'s layer watches for crossings: Noël soft is on, the sleigh is due, or `scene`'s crossing is playing. The last
    /// one keeps the arrival sleigh going on 25–26/12 (or with automatic themes off), when nothing else is on once it started.
    func shouldWatch(scene: UUID, theme: SeasonalTheme?) -> Bool {
        theme?.hasCrossings == true || arrivalPending || current?.scene == scene
    }

    /// Where a scene's crossings play: the band between the bars, in a window `windowHeight` high.
    struct Stage: Equatable {
        var area: CGSize
        var windowHeight: CGFloat
        /// What may cross while the theme's crossings are on (Noël soft's by default, Spooktober soft's for LOT-191).
        var items: [NoelCrossingItem] = NoelCrossingItem.crossing
    }

    /// The crossing `scene` may start now on `stage`: the arrival item when due, else one of `stage.items` once the gap is spent while
    /// `crossingsOn` (Noël soft, Spooktober soft). Nothing while the screen is not clear (THEMES.md §4 rule 5), while another
    /// crossing plays, or without animations (the arrival is then dropped, so the alert comes alone).
    func crossing(
        for scene: UUID, on stage: Stage, screen: SeasonalThemeModel.ScreenState, animationsAllowed: Bool, crossingsOn: Bool
    ) -> Crossing? {
        if let current { return current.scene == scene ? current : nil }
        guard animationsAllowed else {
            arrivalPending = false
            return nil
        }
        guard screen.allowsAlert, activeScenes.contains(scene) else { return nil }
        if arrivalPending {
            let item = pick(from: arrivalItems)
            let size = Self.arrivalSize(of: item, window: stage.windowHeight, areaWidth: stage.area.width)
            // Kept pending until it starts: a layer not laid out yet (empty area) must not lose it.
            let launch = Launch(item: item, size: size, duration: CrossingPath.maxDuration, isArrival: true)
            let arrival = start(launch, area: stage.area, scene: scene)
            if arrival != nil { arrivalPending = false }
            return arrival
        }
        guard crossingsOn, !stage.items.isEmpty, foregroundTime >= nextGap else { return nil }
        let item = pick(from: stage.items)
        let duration = 2.2 + 0.8 * random.unit()
        let height = item == .lightning ? LightningStrike.flashHeight : Self.itemHeight
        return start(Launch(item: item, size: item.size(height: height), duration: duration), area: stage.area, scene: scene)
    }

    private func pick(from items: [NoelCrossingItem]) -> NoelCrossingItem {
        items[min(Int(random.unit() * Double(items.count)), items.count - 1)]
    }

    /// `scene`'s screen changed: a crossing stops as soon as the keyboard, a sheet, an alert or the lock comes up.
    func screenChanged(for scene: UUID, screen: SeasonalThemeModel.ScreenState) {
        if current?.scene == scene, !screen.allowsAlert { current = nil }
    }

    /// The crossing `id` reached the far edge, or was tapped away (THEMES.md §4 rule 3).
    func finish(_ id: Int) {
        if current?.id == id { current = nil }
    }

    /// The crossing `id` was cut before its end by its layer (a rotation, a split view or Stage Manager resize restarts the
    /// watch): the arrival sleigh is due again, so it still plays before the alert, while less than `arrivalReplayWindow` has
    /// passed since it first started; after that the alert comes alone. An ordinary object just ends.
    func interrupt(_ id: Int) {
        guard let current, current.id == id else { return }
        self.current = nil
        if current.isArrival, let first = arrivalFirstStart, now().timeIntervalSince(first) < Self.arrivalReplayWindow {
            arrivalPending = true
        }
    }

    /// `scene` went away: its crossing stops, and it no longer counts as active.
    func release(scene: UUID) {
        sceneChanged(scene, active: false)
    }

    /// What starts: `item` at `size`, for `duration` (the arrival at full length, `CrossingPath.maxDuration`).
    private struct Launch {
        var item: NoelCrossingItem
        var size: CGSize
        var duration: TimeInterval
        var isArrival = false
    }

    /// Starts `launch` across `area`.
    private func start(_ launch: Launch, area: CGSize, scene: UUID) -> Crossing? {
        let item = launch.item
        let size = launch.size
        let arrival = launch.isArrival
        guard let shape = shape(of: launch, area: area) else { return nil }
        // The gap restarts with the crossing: the next one waits at least 20 minutes of foreground time.
        let date = now()
        foregroundBefore = 0
        activeSince = date
        nextGap = Self.minGap + random.unit() * (Self.maxGap - Self.minGap)
        lastID += 1
        if arrival, arrivalFirstStart == nil { arrivalFirstStart = date }
        let crossing = Crossing(
            id: lastID, item: item, size: size, path: shape.path, isArrival: arrival, flashes: shape.flashes, scene: scene
        )
        current = crossing
        haptics.impact(.light)
        return crossing
    }

    /// The line `item` follows, or for lightning the five flashes (it does not travel: its path stays at the middle of the area).
    private func shape(of launch: Launch, area: CGSize) -> Shape? {
        let item = launch.item
        let size = launch.size
        if item == .lightning {
            let flashes = LightningStrike.flashes(in: area, size: size, random: random)
            guard !flashes.isEmpty else { return nil }
            let middle = CGPoint(x: area.width / 2, y: area.height / 2)
            let still = CrossingPath(
                start: middle, end: middle, duration: LightningStrike.window, entry: .leading, mirrored: false, rotation: 0
            )
            return Shape(path: still, flashes: flashes)
        }
        let horizontalOnly = item == .sleigh || launch.isArrival
        let traits = CrossingPath.Traits(
            size: size, directional: item.isDirectional, facesLeading: item.facesLeading, horizontalOnly: horizontalOnly,
            maxTilt: horizontalOnly ? .pi / 12 : .pi / 6, duration: launch.duration
        )
        return CrossingPath.random(in: area, for: traits, random: random).map { Shape(path: $0, flashes: []) }
    }

    /// How a crossing plays: a line, or flashes.
    private struct Shape {
        var path: CrossingPath
        var flashes: [LightningFlash]
    }
}
