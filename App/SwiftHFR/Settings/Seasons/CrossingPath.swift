import CoreGraphics
import Foundation

/// A source of random numbers in 0..<1, injected so the crossings are deterministic in tests (LOT-166).
@MainActor
protocol SeasonalRandom: AnyObject {
    /// A value in 0..<1.
    func unit() -> Double
}

/// The system generator: the app's crossings.
@MainActor
final class SystemSeasonalRandom: SeasonalRandom {
    private var generator = SystemRandomNumberGenerator()

    /// A value in 0..<1.
    func unit() -> Double { Double.random(in: 0..<1, using: &generator) }
}

/// The straight line a crossing object follows (THEMES.md §4 rule 4): it enters by one edge of the area, fully outside it, and
/// leaves by the opposite edge, fully outside again, at a random angle and in a random direction. Pure geometry, in points of the
/// area it was made for.
struct CrossingPath: Equatable, Sendable {
    /// The edge an object enters by; it leaves by the opposite one.
    enum Edge: Equatable, Sendable {
        case leading, trailing, top, bottom
    }

    /// The object's centre when it starts, outside the area.
    var start: CGPoint
    /// The object's centre when it ends, outside the area on the opposite side.
    var end: CGPoint
    /// Seconds from `start` to `end` (≤ 3 s, THEMES.md §4 rule 4).
    var duration: TimeInterval
    /// Where it enters.
    var entry: Edge
    /// The art is drawn mirrored as a whole (sleigh and reindeer together, THEMES.md §6 rule 3), then turned by `rotation`.
    var mirrored: Bool
    /// The turn, in radians, applied after the mirror (clockwise on screen), so the art faces where it goes.
    var rotation: Double

    /// The longest crossing (THEMES.md §4 rule 4).
    static let maxDuration: TimeInterval = 3

    /// The centre at `progress` (0...1, clamped).
    func point(at progress: Double) -> CGPoint {
        let clamped = min(max(progress.isFinite ? progress : 0, 0), 1)
        return CGPoint(x: start.x + (end.x - start.x) * clamped, y: start.y + (end.y - start.y) * clamped)
    }

    /// The unit vector the art faces once mirrored and turned; for art drawn facing the trailing edge (the sleigh's renders).
    var facing: CGVector {
        let sign: Double = mirrored ? -1 : 1
        return CGVector(dx: sign * cos(rotation), dy: sign * sin(rotation))
    }

    /// What crosses: its size, whether it has a front, how it may enter and how long it takes.
    struct Traits: Sendable {
        /// The art's size, in points.
        var size: CGSize
        /// Art drawn facing the trailing edge faces its travel; other art stays upright.
        var directional: Bool
        /// It enters by a side only (the sleigh).
        var horizontalOnly: Bool
        /// The largest angle to the crossing axis, in radians.
        var maxTilt: Double
        /// The time asked for, capped at `maxDuration`.
        var duration: TimeInterval
    }

    /// A random path across `area` for an object of `traits`.
    @MainActor
    static func random(in area: CGSize, for traits: Traits, random: any SeasonalRandom) -> CrossingPath? {
        let size = traits.size
        let directional = traits.directional
        let horizontalOnly = traits.horizontalOnly
        let maxTilt = traits.maxTilt
        let duration = traits.duration
        guard area.width > 0, area.height > 0, size.width > 0, size.height > 0 else { return nil }
        let horizontal = horizontalOnly || random.unit() < 0.5
        let forward = random.unit() < 0.5
        // Half the diagonal: the object is outside the area at both ends, however it is turned.
        let reach = hypot(size.width, size.height) / 2
        // Along the travel axis and across it.
        let along = (horizontal ? area.width : area.height) + 2 * reach
        let across = horizontal ? area.height : area.width
        let margin = min((horizontal ? size.height : size.width) / 2, across / 2)
        let room = across - 2 * margin
        // The tilt, limited so the line stays inside the area across the axis.
        let limit = min(abs(maxTilt), atan(room / along))
        let tilt = (random.unit() * 2 - 1) * limit
        let drift = tan(tilt) * along
        let first = margin + max(0, -drift) + random.unit() * max(0, room - abs(drift))
        let from = horizontal ? CGPoint(x: -reach, y: first) : CGPoint(x: first, y: -reach)
        let target = horizontal ? CGPoint(x: area.width + reach, y: first + drift) : CGPoint(x: first + drift, y: area.height + reach)
        let start = forward ? from : target
        let end = forward ? target : from
        let entry: Edge = horizontal ? (forward ? .leading : .trailing) : (forward ? .top : .bottom)
        let (mirrored, rotation) = orientation(from: start, to: end, directional: directional)
        return CrossingPath(
            start: start, end: end, duration: min(duration, maxDuration), entry: entry, mirrored: mirrored, rotation: rotation
        )
    }

    /// Art drawn facing the trailing edge is mirrored when it goes towards the leading one, then turned along the line; upright
    /// art is left as drawn.
    private static func orientation(from start: CGPoint, to end: CGPoint, directional: Bool) -> (Bool, Double) {
        guard directional else { return (false, 0) }
        let deltaX = end.x - start.x
        let deltaY = end.y - start.y
        return deltaX < 0 ? (true, atan2(-deltaY, -deltaX)) : (false, atan2(deltaY, deltaX))
    }
}
