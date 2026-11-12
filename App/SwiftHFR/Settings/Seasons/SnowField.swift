import CoreGraphics
import Foundation

/// Noël soft's falling snow as pure geometry (LOT-166): flakes drawn procedurally, so no art file is shipped (legacy's
/// `SuperHFRplus/Assets/UI/snow/` frames have no stated origin or licence). Positions are a function of time, so a paused
/// timeline draws nothing new and a test needs no waiting.
struct SnowField: Sendable {
    /// One flake: where it starts and how it falls, in fractions of the area.
    struct Flake: Sendable {
        /// Horizontal position, 0...1 of the width.
        var column: Double
        /// Starting height, 0...1 of the height.
        var phase: Double
        /// Fraction of the height fallen per second.
        var speed: Double
        /// Radius in points.
        var radius: Double
        /// Sideways sway in points.
        var sway: Double
        /// Opacity, light: the snow stays behind the text in importance.
        var opacity: Double
    }

    /// The flakes, few and slow: « neige légère » (THEMES.md §2).
    let flakes: [Flake]

    /// The app's snow: 28 flakes from a fixed seed, the same on every launch.
    static let light = SnowField(count: 28, seed: 0x2512)

    /// `count` flakes from `seed`.
    init(count: Int, seed: UInt64) {
        var generator = SplitMix64(state: seed)
        flakes = (0..<max(count, 0)).map { _ in
            Flake(
                column: generator.unit(), phase: generator.unit(), speed: 0.04 + 0.05 * generator.unit(),
                radius: 1.5 + 1.5 * generator.unit(), sway: 4 + 8 * generator.unit(), opacity: 0.55 + 0.35 * generator.unit()
            )
        }
    }

    /// Every flake's centre at `time` (seconds) inside `size`, wrapping at the bottom and the sides.
    func positions(at time: TimeInterval, in size: CGSize) -> [CGPoint] {
        guard size.width > 0, size.height > 0, time.isFinite else { return [] }
        return flakes.map { flake in
            let fallen = (flake.phase + time * flake.speed).truncatingRemainder(dividingBy: 1)
            let swayed = flake.column * size.width + sin(time * 0.6 + flake.phase * 2 * .pi) * flake.sway
            let x = swayed.truncatingRemainder(dividingBy: size.width)
            return CGPoint(x: x < 0 ? x + size.width : x, y: fallen * size.height)
        }
    }
}

/// A small deterministic generator (SplitMix64), so the field is the same everywhere and in tests.
private struct SplitMix64 {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }

    /// A value in 0..<1.
    mutating func unit() -> Double { Double(next() >> 11) / Double(UInt64(1) << 53) }
}
