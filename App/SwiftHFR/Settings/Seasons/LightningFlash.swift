import CoreGraphics
import Foundation

/// One flash of the lightning that crosses Spooktober soft (THEMES.md §4 rule 4): it appears at `center` at `start` seconds after
/// the crossing began and shows for `duration`.
struct LightningFlash: Equatable, Sendable {
    var start: TimeInterval
    var duration: TimeInterval
    var center: CGPoint

    /// The flash is on at `elapsed` seconds into the crossing.
    func isVisible(at elapsed: TimeInterval) -> Bool { elapsed >= start && elapsed < start + duration }
}

/// The lightning's schedule (operator, 2026-10-28; tokens `crossingItems.lightning`): five flashes of about 0.3 s at random places,
/// all within 3 s. Pure geometry and timing, so the limits are tested.
enum LightningStrike {
    static let flashCount = 5
    static let flashDuration: TimeInterval = 0.3
    /// All the flashes end within this (THEMES.md §4 rule 4: crossings last at most 3 s).
    static let window: TimeInterval = CrossingPath.maxDuration
    /// A flash's height, in points: one of the small crossing objects, a bit larger so a bolt reads.
    static let flashHeight: CGFloat = 120

    /// Five flashes in `area`, one per slot of `window / flashCount`, each starting at a random moment of its slot that still lets
    /// it end inside it, and standing at a random place with its whole bolt (of `size`) inside `area`.
    @MainActor
    static func flashes(in area: CGSize, size: CGSize, random: any SeasonalRandom) -> [LightningFlash] {
        guard area.width > 0, area.height > 0, size.width > 0, size.height > 0 else { return [] }
        let slot = window / Double(flashCount)
        let width = min(size.width, area.width)
        let height = min(size.height, area.height)
        return (0..<flashCount).map { index in
            let start = Double(index) * slot + random.unit() * (slot - flashDuration)
            let x = width / 2 + random.unit() * (area.width - width)
            let y = height / 2 + random.unit() * (area.height - height)
            return LightningFlash(start: start, duration: flashDuration, center: CGPoint(x: x, y: y))
        }
    }

    /// The flash that is on at `elapsed`, if any (the slots never overlap).
    static func visibleFlash(at elapsed: TimeInterval, in flashes: [LightningFlash]) -> LightningFlash? {
        flashes.first { $0.isVisible(at: elapsed) }
    }
}
