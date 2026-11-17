import CoreGraphics
import Foundation

/// Where the packing elves stand in the band between the bars (THEMES.md §5): up to three, side by side at even fractions of
/// the band's width, rising from its bottom edge, hopping while they pack, and going back down before the end. Pure, so the
/// limits are tested.
nonisolated enum NoelPackingLayout {
    /// Width over height of the elf: the operator's `noel_elf` render trimmed to its alpha > 8 box, 364 × 780 (the trim of
    /// `tooling/art/noel-crossings/derive.swift`; this PNG was cut and scaled the same way with PIL, see the lot spec).
    static let elfAspectRatio: Double = 364.0 / 780
    /// The tallest elf, in points.
    static let maxElfHeight: CGFloat = 180
    /// At most this many elves.
    static let maxElves = 3
    /// The share of the run spent rising, and again going down.
    static let riseShare = 0.2
    /// Each elf's hop while it packs, as a share of its height.
    static let hopShare = 0.06

    /// An elf's height: a fifth of the window, at most `maxElfHeight`, never taller than the band.
    static func elfHeight(window: CGFloat, band: CGFloat) -> CGFloat {
        min(max(window, 0) / 5, maxElfHeight, max(band, 0))
    }

    /// How far the elves stand out of the band's bottom edge at `progress` (0…1 of the run): 0 hidden below it, 1 fully up.
    static func rise(at progress: Double) -> Double {
        let progress = min(max(progress, 0), 1)
        let rising = min(progress / riseShare, 1)
        let falling = min((1 - progress) / riseShare, 1)
        return min(rising, falling)
    }

    /// The hop's amplitude while the elves are fully up: 0 when the rise ends and when the descent starts, 1 halfway.
    static func hopEnvelope(at progress: Double) -> Double {
        let span = 1 - 2 * riseShare
        let within = (min(max(progress, 0), 1) - riseShare) / span
        return within <= 0 || within >= 1 ? 0 : sin(within * .pi)
    }

    /// The elves' frames in a band of `area` at `progress`, in a window `windowHeight` high: as many as fit at even fractions of
    /// the width with at least a quarter of an elf between them and the edges (none in a band too narrow for one).
    static func frames(in area: CGSize, windowHeight: CGFloat, progress: Double) -> [CGRect] {
        let height = elfHeight(window: windowHeight, band: area.height)
        let width = height * elfAspectRatio
        guard height > 0, width > 0, area.width > 0 else { return [] }
        // `count` centres at width / (count + 1) apart: that step is at least 1.25 elf widths.
        let count = min(maxElves, Int(area.width / (width * 1.25)) - 1)
        guard count > 0 else { return [] }
        let lift = rise(at: progress)
        return (0..<count).map { index in
            let centre = area.width * CGFloat(index + 1) / CGFloat(count + 1)
            // Each elf hops on its own beat while fully up, its amplitude easing in and out so nothing jumps when the rise
            // ends or the descent starts; never above the band's top.
            let hop = lift < 1 ? 0 : height * hopShare * hopEnvelope(at: progress) * abs(sin(progress * .pi * 8 + Double(index) * 1.3))
            let top = area.height - height * lift - hop
            return CGRect(x: centre - width / 2, y: max(top, 0), width: width, height: height)
        }
    }
}
